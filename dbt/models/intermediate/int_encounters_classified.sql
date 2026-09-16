-- cardiology split happens here, not at ingestion: ICD-10 chapter IX
-- (circulatory system) is codes I00-I99, so a leading "I" is enough
with encounters as (
    select * from {{ ref('stg_encounters') }}
)

select
    *,
    icd10_code like 'I%' as is_cardiology
from encounters
