# Vélib’ Daily Insights – Data Pipeline AWS

## 📌 Contexte
Ce projet a été réalisé dans le cadre du cours **Data Pipeline Cloud (EPISEN)**.  
L’objectif est de concevoir un **pipeline de données automatisé sur AWS**, à partir des données Open Data Vélib’, afin de produire des indicateurs métier exploitables via un dashboard.

---

## 🏗️ Architecture Générale
Pipeline simple et automatisé :

EventBridge → Lambda → S3 (Raw) → Glue Crawler → Athena → QuickSight

- Ingestion régulière des données Vélib’
- Stockage des données brutes dans S3
- Catalogage automatique avec Glue
- Requêtes analytiques avec Athena
- Visualisation des KPI via QuickSight

---

## 🌍 Région AWS
- **Région utilisée** : `us-east-1` 
> ⚠️ Toutes les ressources doivent être créées dans cette région.

---

## 🧩 Convention de nommage

### Projet
- **Project name** : `velib-insights`

### S3
- **Bucket principal** : `velib-insights-naw-seu-2326`

---

## ⚙️ Ressources AWS

### Lambda
- **Nom** : `velib_ingest_lambda`
- **Rôle** : récupération des données Vélib’ via l’API Open Data et écriture dans S3

### EventBridge
- **Rule** : `velib_ingest_schedule`
- **Fréquence** : toutes les **15 minutes**

### AWS Glue
- **Database** : `velib_db`
- **Crawler** : `velib_raw_crawler`
- **Rôle** : catalogage automatique des données S3

### Athena
- **Workgroup** : `velib_workgroup`
- **Rôle** : requêtes SQL pour calcul des KPI

---

## 🏷️ Tags AWS
Les ressources AWS sont taguées avec les clés suivantes :

- `project` = `velib-insights`
- `owner` = `team-naw-seu`
- `course` = `data-pipeline-episen`

---

## 📊 KPI analysés
- Taux de remplissage des stations
- Stations en pénurie (0 vélo disponible)
- Stations saturées (0 borne libre ou > 90%)
- Top 10 stations critiques
- Analyse par arrondissement
- Analyse par tranche horaire

---

## 👥 Organisation de l’équipe
- **Infra & Ingestion** : S3, Lambda, EventBridge, Glue, Terraform
- **Analytics & Visualisation** : Athena (SQL), QuickSight, KPI, slides client

---

## 🚀 Déploiement
L’infrastructure est déployée via **Infrastructure as Code (Terraform)**.  
Un seul environnement AWS est utilisé (contrainte du lab étudiant).

---

## 📎 Remarques
- Projet conçu comme un **PoC client**
- Architecture volontairement simple, robuste et peu coûteuse
- Aucun Machine Learning utilisé (conformément aux attentes du cours)

---

## 🎓 Cours
EPISEN – Data Pipeline Cloud  
Année universitaire 2025–2026