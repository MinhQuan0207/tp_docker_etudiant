# Compte Rendu — Exercice 5 : Scraper des cibles Prometheus et expédier vers Mimir

**Date :** 2026-06-10  
**Auteur :** mqnguyen  
**Durée effective :** ~45 min  
**Section TP :** Prometheus / Mimir  

---

## Objectif

Déployer un backend de métriques compatible Prometheus, installer `node-exporter`, configurer Alloy pour découvrir et scraper les endpoints Kubernetes, puis envoyer les métriques vers Mimir afin de les visualiser dans Grafana.

---

## Environnement

| Élément | Valeur |
|---|---|
| Cluster | kind `otel-lab` |
| Namespace observabilité | `observability` |
| Pod Alloy | `alloy-2sljb` |
| Pod Mimir final | `mimir-c6ccbfdfb-42rt8` |
| Backend métriques | Grafana Mimir |
| Exporteur de cibles | `prometheus-node-exporter` |
| UI visualisation | Grafana |
| Port Grafana | `3000` |
| Port Mimir API/Prometheus | `9009` |
| Port Alloy UI | `12345` |

---

## Objectif technique atteint

L’exercice demandait d’installer Mimir, `node-exporter` et Grafana via Helm, puis de configurer Alloy avec une chaîne de découverte Kubernetes, de scrape Prometheus et de `remote_write` vers Mimir.

Le résultat attendu était de pouvoir interroger Mimir avec la métrique `up` et de retrouver un job `node-exporter` dans Grafana Explore.

---

## Déploiements réalisés

### 1. Backend Mimir

La tentative initiale avec le chart `grafana/mimir-distributed` a déployé de nombreux composants distribués (`distributor`, `querier`, `ingester-zone-*`, `store-gateway`, `kafka`, etc.), ce qui n’était pas adapté au cluster kind du lab.

Pour stabiliser l’exercice, un déploiement Mimir simplifié a été appliqué avec un manifeste `mimir-simple.yaml` contenant :
- un `ConfigMap` avec `target: all`,
- un `Deployment` Mimir unique,
- un `Service` `mimir` sur le port `9009`,
- un stockage local `filesystem`,
- un `replication_factor: 1`.

### 2. node-exporter

Le chart `prometheus-community/prometheus-node-exporter` a été installé dans le namespace `observability`.

### 3. Grafana

Grafana a été installé dans le namespace `observability` afin d’interroger Mimir comme datasource Prometheus.

### 4. Alloy

La configuration Alloy a été étendue avec des composants Prometheus natifs :
- `discovery.kubernetes`
- `discovery.relabel`
- `prometheus.scrape`
- `prometheus.remote_write`

Le pipeline OTLP des exercices précédents a été conservé, puis complété par une seconde chaîne dédiée aux métriques Prometheus.

---

## Configuration Alloy mise en place

La partie ajoutée dans `alloy-values.yaml` pour l’exercice 5 repose sur quatre composants :

1. **Découverte Kubernetes**
   - découverte des endpoints `node-exporter` dans le namespace `observability`

2. **Relabeling**
   - filtrage du bon port
   - ajout d’un label `node`

3. **Scrape Prometheus**
   - collecte périodique des métriques `node-exporter`

4. **Remote write**
   - envoi des séries vers Mimir sur :
   - `http://mimir.observability.svc:9009/api/v1/push`

Exemple de logique utilisée :

```alloy
discovery.kubernetes "node_exporter" {
  role = "endpoints"
  namespaces {
    names = ["observability"]
  }
}

discovery.relabel "node_exporter" {
  targets = discovery.kubernetes.node_exporter.targets
}

prometheus.scrape "node_exporter" {
  targets         = discovery.relabel.node_exporter.output
  forward_to      = [prometheus.remote_write.mimir.receiver]
  scrape_interval = "30s"
  job_name        = "node-exporter"
}

prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir.observability.svc:9009/api/v1/push"
  }
}
```

---

## Vérifications effectuées

### Pods en fonctionnement

Vérification finale observée :

```bash
kubectl -n observability get pods
```

Résultat utile :

- `alloy-2sljb` → `2/2 Running`
- `mimir-c6ccbfdfb-42rt8` → `1/1 Running`

### Réponse de Mimir

Un port-forward a été utilisé vers le service `mimir` sur `9009`, puis un test de disponibilité a été réalisé :

```bash
curl -s http://localhost:9009/ready
```

Le service répondait bien via le port-forward.

### Vérification de l’ingestion des métriques

La commande suivante a confirmé la présence de la métrique `up` dans Mimir :

```bash
curl -s "http://localhost:9009/prometheus/api/v1/query?query=up" | python3 -m json.tool | grep -E "job|value"
```

Sortie observée :

```text
"job": "node-exporter"
"value": [
```

Cela confirme que :
- Alloy scrape bien `node-exporter`
- Alloy pousse bien les métriques dans Mimir
- Mimir stocke et expose bien les séries Prometheus

---

## Accès distant depuis un autre PC

Le test Grafana a été réalisé depuis un second PC connecté en SSH à la VM Debian.

Le problème rencontré venait du fait que `kubectl port-forward` écoute par défaut sur `127.0.0.1`, donc seulement sur la VM locale. Pour rendre Grafana accessible depuis le réseau local, le port-forward a été relancé avec :

```bash
kubectl -n observability port-forward svc/grafana 3000:80 --address 0.0.0.0 &
```

Accès final fonctionnel :

- `http://192.168.1.72:3000`

La même méthode peut être utilisée pour Alloy (`12345`) et Mimir (`9009`).

---

## Problèmes rencontrés

### 1. Chart Mimir trop lourd pour le lab

La première installation de `grafana/mimir-distributed` a lancé une topologie distribuée complète :
- `distributor`
- `querier`
- `ingester-zone-*`
- `store-gateway`
- `kafka`
- `ruler`
- `alertmanager`

Conséquence :
- nombreux pods en `CrashLoopBackOff`
- consommation trop importante pour le cluster local
- exercice bloqué

**Solution :**
remplacement par un manifeste `mimir-simple.yaml` avec une seule instance Mimir.

### 2. Repo Helm manquant pour node-exporter

Erreur rencontrée :

```text
Error: repo prometheus-community not found
```

**Solution :**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Puis installation de `prometheus-node-exporter`.

### 3. Fichier `alloy-values.yaml` absent dans `ex05`

Le fichier n’avait pas été recopié dans le dossier de travail, ce qui empêchait le `helm upgrade` d’Alloy.

**Solution :**
recréation directe du fichier `alloy-values.yaml` dans `~/tp-observabilite/otel-alloy-ex05/`.

### 4. Port-forwards déjà occupés

Plusieurs erreurs `address already in use` sont apparues sur `3000`, `9009` et `12345`.

**Cause :**
anciens processus `kubectl port-forward` toujours actifs.

**Solution :**
nettoyage des processus puis relance avec `--address 0.0.0.0`.

### 5. Accès Grafana refusé depuis un autre PC

Erreur navigateur :

```text
ERR_CONNECTION_REFUSED
192.168.1.72 n'autorise pas la connexion
```

**Cause :**
port-forward lié à `127.0.0.1` au lieu de `0.0.0.0`.

**Solution :**
utilisation de `--address 0.0.0.0`.

---

## Résultat final

L’exercice est réussi.

### Validation fonctionnelle

- ✅ Alloy fonctionne toujours
- ✅ Mimir fonctionne en mode simple
- ✅ node-exporter est déployé
- ✅ Alloy découvre et scrape node-exporter
- ✅ Alloy pousse les métriques vers Mimir
- ✅ La requête `up` dans Mimir retourne le job `node-exporter`
- ✅ Grafana est accessible depuis un autre PC via l’IP de la VM

---

## Ce qu’il faut retenir

- `discovery.kubernetes` permet à Alloy de découvrir dynamiquement des cibles Prometheus dans Kubernetes.
- `prometheus.scrape` collecte les métriques des endpoints découverts.
- `prometheus.remote_write` permet d’expédier les séries vers Mimir.
- Dans un lab léger, un backend monolithique ou simplifié est souvent plus réaliste qu’un chart distribué complet.
- `kubectl port-forward --address 0.0.0.0` est indispensable pour accéder aux services depuis un autre poste que la VM.

---

## Conclusion

L’objectif de l’exercice 5 est atteint : les métriques système exposées par `node-exporter` sont bien collectées par Alloy et stockées dans Mimir, puis consultables dans Grafana.

Cet exercice introduit la chaîne complète **Prometheus scrape → Alloy → Mimir → Grafana**, qui servira de base pour l’exercice 6 sur les métriques OpenTelemetry applicatives et leur conversion vers le monde Prometheus.
