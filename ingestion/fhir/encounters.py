"""Business logic for the FHIR encounters feed: what to generate, how to shape it.

No orchestrator imports here on purpose - plain Python, testable and
importable on its own, so swapping Airflow for something else later only
means rewriting the orchestration adapter, not this.
"""
import json
import random
import uuid
from datetime import datetime, timezone
from pathlib import Path

import yaml

TABLES_CONFIG_PATH = Path(__file__).parent.parent / "config" / "tables.yml"

HOSPITAL_NAME = "Riverside General Hospital"
HOSPITAL_STATE = "IL"
ENCOUNTER_CLASSES = ["inpatient", "emergency"]

# mixed specialties on purpose, including cardiology (I-codes) - no
# grouping/labeling here, that split happens downstream in dbt
ICD10_CODES = [
    "I10", "I21", "I50", "I48", "I63",
    "J44", "J18", "J45",
    "E11", "E10", "E66",
    "K35", "K80", "K29",
    "S72", "M54", "S82",
    "A09", "B34", "U07.1",
]

WRITE_DISPOSITIONS = {"append": "WRITE_APPEND", "truncate": "WRITE_TRUNCATE"}


def table_config() -> dict:
    # only one entry in the registry today, so just grab it
    return yaml.safe_load(TABLES_CONFIG_PATH.read_text())["tables"][0]


def _fake_encounter(encounter_class: str) -> dict:
    return {
        "encounter_id": str(uuid.uuid4()),
        "encounter_class": encounter_class,
        "icd10_code": random.choice(ICD10_CODES),
        "patient_age": random.randint(0, 100),
        "patient_sex": random.choice(["M", "F"]),
        "hospital_name": HOSPITAL_NAME,
        "hospital_state": HOSPITAL_STATE,
        "charge_amount_usd": round(random.uniform(150.0, 25000.0), 2),
        "encounter_datetime": datetime.now(timezone.utc).isoformat(),
    }


def generate_encounters(n_per_class: int) -> list[dict]:
    return [_fake_encounter(c) for c in ENCOUNTER_CLASSES for _ in range(n_per_class)]


def to_ndjson(records: list[dict]) -> str:
    return "\n".join(json.dumps(r) for r in records)
