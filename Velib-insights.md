# Vélib’ Daily Insights – Data Pipeline AWS

## Contexte
Ce projet a été réalisé dans le cadre du cours **Data Pipeline Cloud (EPISEN)**.  
L’objectif est de concevoir un **pipeline de données automatisé sur AWS**, à partir des données **Open Data Vélib’**, afin de produire des **KPI métier exploitables** via des requêtes analytiques et une visualisation cible.

---

## Architecture Générale
Pipeline automatisé en **deux workflows complémentaires** :

### Workflow 1 — Pipeline Data (planifié)
EventBridge → Step Functions → Lambda → S3 (Raw) → Glue Job → S3 (Clean) → Glue Crawler → Athena

- Ingestion régulière des données Vélib’ (snapshot)
- Nettoyage et typage des données
- Stockage optimisé en Parquet
- Catalogage automatique
- Données prêtes à l’analyse

### Workflow 2 — KPI & Analytics (manuel – démo)
Step Functions → Athena (CREATE OR REPLACE VIEW)

- Création automatisée des vues KPI
- Aucune saisie manuelle de requêtes SQL
- Démonstration rapide et reproductible

---

## Région AWS
- **Région utilisée** : `us-east-1`  
> ⚠️ Toutes les ressources sont déployées dans cette région (contrainte du lab étudiant).

---

## Convention de nommage

### Projet
- **Project name** : `velib-insights`

### S3
- **Bucket principal** : `velib-insights-naw-seu-2326`

#### Organisation S3
- `raw/source=velib/` : données brutes JSON (snapshots)
- `clean/source=velib/` : données nettoyées (Parquet)
- `glue/scripts/` : scripts Glue
- `glue/tmp/` : répertoire temporaire Glue
- `athena-results/` : résultats Athena

---

## Ressources AWS

### Lambda
- **Nom** : `velib_ingest_lambda`
- **Rôle** : appel de l’API Open Data Vélib et écriture des snapshots dans S3 (raw)

### EventBridge
- **Schedule** : `velib_pipeline_schedule`
- **Fréquence** : toutes les **15 minutes**
- **Rôle** : déclenchement automatique du pipeline

### Step Functions

#### 1️ Pipeline Data
- **Nom** : `velib_pipeline`
- **Étapes** :
  1. Invoke Lambda (ingestion)
  2. Attente courte
  3. Glue Job (nettoyage)
  4. Glue Crawler (catalogage)

#### 2️ KPI Views (manuel)
- **Nom** : `velib_kpi_views`
- **Rôle** : exécution automatique des requêtes SQL de création de vues KPI dans Athena

---

### AWS Glue
- **Database** : `velib_db_tf`
- **Glue Job** : `velib_clean_job`
  - Nettoyage, typage, enrichissement
  - Sortie en Parquet partitionné (date / hour)
- **Crawler** : `velib_clean_crawler`
  - Création de la table `source_velib`

---

### Athena
- **Workgroup** : `velib_workgroup`
- **Rôle** :
  - Analyse des données clean
  - Support des vues KPI

---

## Tags AWS
Toutes les ressources sont taguées avec :

- `project` = `velib-insights`
- `owner` = `team-naw-seu`
- `course` = `data-pipeline-episen`

---

##  KPI analysés (via vues Athena)
- Taux de remplissage des stations
- Stations en pénurie (0 vélo)
- Stations saturées (0 borne ou ≥ 90 %)
- Top 10 stations critiques (fenêtre 2h)
- Analyse par arrondissement

---

## Organisation de l’équipe
- **Infra & Orchestration** : Terraform, S3, Lambda, Step Functions, Glue
- **Data Processing & Analytics** : Glue Job (clean), Athena (SQL), KPI, slides

---

## Déploiement
- Infrastructure déployée via **Terraform (IaC)**
- Pipeline **largement automatisé** (déploiement + exécution)
- Step Function KPI déclenchée manuellement pour la démonstration

---

## Coûts (ordre de grandeur)
- Lambda, EventBridge, Step Functions, S3 : **coût négligeable**
- Athena : facturation au volume scanné (faible grâce au Parquet)
- Glue : principal coût (DPU × durée), mais très faible pour ce PoC

---

## Remarques
- Source **Open Data publique**
- Pipeline conçu comme un **PoC client**
- Architecture volontairement simple, robuste et scalable
- Aucun Machine Learning (conformément aux consignes du cours)

---

## Arborescence du projet

```text
velib-terraform/
├── main.tf
├── variables.tf
├── output.tf
│
├── lambda/
│   └── lambda_function.py
│
├── glue/
│   └── velib_clean.py
│
├── kpi_taux_remplissage.sql
├── kpi_shortage.sql
├── kpi_station_saturation.sql
├── kpi_saturation_par_arrondissement.sql
└── kpi_top10_2hour.sql
