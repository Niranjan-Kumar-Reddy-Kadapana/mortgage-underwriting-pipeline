.PHONY: sim init load load-late dbt-empty dbt-silver dbt-gold dbt-all test tf-plan dash

sim:        ## 5k synthetic applications, 5% of bureau records held back as "late"
	python data_simulation/generate_data.py --out data/out --rows 5000 --late-pct 5
init:       ## create stage, file formats and Bronze tables
	python ingestion/load_bronze.py --init --source all --dir data/out
load:
	python ingestion/load_bronze.py --source all --dir data/out
load-late:  ## simulate the delayed credit bureau file arriving
	python ingestion/load_bronze.py --source credit --dir data/out/late
dbt-empty:  ## dry run: builds empty relations so unit tests and schema checks can run
	cd dbt && dbt run --empty --profiles-dir .
dbt-silver:
	cd dbt && dbt build --select tag:silver --exclude tag:gold --profiles-dir .
dbt-gold:
	cd dbt && dbt build --select tag:gold --profiles-dir .
dbt-all: dbt-silver dbt-gold
test:
	pytest -q
tf-plan:
	cd terraform && terraform init && terraform plan
dash:
	streamlit run dashboard/app.py
