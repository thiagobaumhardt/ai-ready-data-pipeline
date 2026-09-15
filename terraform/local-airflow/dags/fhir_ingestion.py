"""
Ingestão de encounters (internação e urgência) via API FHIR.

Simula uma chamada ao endpoint Encounter de uma API FHIR (HL7 FHIR é o
padrão real usado por hospitais americanos para expor esse tipo de dado),
de um hospital fictício nos EUA. Os encounters saem com diagnósticos
(ICD-10-CM) de várias especialidades, para exercitar o filtro de
cardiologia (capítulo I00-I99) nas camadas seguintes do pipeline
(GCS/BigQuery).

Roda dentro do cluster kind (Airflow instalado via Helm, ver
terraform/local-airflow); com KubernetesExecutor, cada execução da task
"encounters" sobe como um Pod isolado no cluster.
"""
from __future__ import annotations

import random
import uuid
from datetime import datetime, timezone

from airflow.sdk import dag, task

HOSPITAL_NAME = "Riverside General Hospital"
HOSPITAL_STATE = "IL"

# Mistura proposital de especialidades — inclui cardiology (ICD-10-CM I00-I99)
# junto com outros capítulos, para depois filtrar só os casos de cardio.
ICD10_BY_SPECIALTY = {
    "cardiology": ["I10", "I21", "I50", "I48", "I63"],
    "pulmonology": ["J44", "J18", "J45"],
    "endocrinology": ["E11", "E10", "E66"],
    "gastroenterology": ["K35", "K80", "K29"],
    "orthopedics": ["S72", "M54", "S82"],
    "infectious_disease": ["A09", "B34", "U07.1"],
}

ENCOUNTER_CLASSES = ["inpatient", "emergency"]


def _simulate_fhir_encounter_request(encounter_class: str) -> dict:
    """Simulates a call to a FHIR API Encounter endpoint, returning a synthetic encounter."""
    specialty = random.choice(list(ICD10_BY_SPECIALTY.keys()))
    icd10_code = random.choice(ICD10_BY_SPECIALTY[specialty])

    return {
        "encounter_id": str(uuid.uuid4()),
        "encounter_class": encounter_class,
        "specialty": specialty,
        "icd10_code": icd10_code,
        "is_cardiology": specialty == "cardiology",
        "patient_age": random.randint(0, 100),
        "patient_sex": random.choice(["M", "F"]),
        "hospital_name": HOSPITAL_NAME,
        "hospital_state": HOSPITAL_STATE,
        "charge_amount_usd": round(random.uniform(150.0, 25000.0), 2),
        "encounter_datetime": datetime.now(timezone.utc).isoformat(),
    }


@dag(
    dag_id="fhir_ingestion",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["ingestion", "fhir", "cardiology", "encounters"],
)
def fhir_ingestion():
    @task
    def encounters(n_per_class: int = 20) -> list[dict]:
        results = [
            _simulate_fhir_encounter_request(encounter_class)
            for encounter_class in ENCOUNTER_CLASSES
            for _ in range(n_per_class)
        ]

        cardiology_encounters = [e for e in results if e["is_cardiology"]]
        print(f"Total encounters: {len(results)} | cardiology: {len(cardiology_encounters)}")

        return results

    encounters()


fhir_ingestion()
