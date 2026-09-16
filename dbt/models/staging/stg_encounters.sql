with source as (
    select * from {{ source('raw_data', 'raw_encounters') }}
)

select
    encounter_id,
    encounter_class,
    icd10_code,
    patient_age,
    patient_sex,
    hospital_name,
    hospital_state,
    charge_amount_usd,
    cast(encounter_datetime as timestamp) as encounter_datetime
from source
