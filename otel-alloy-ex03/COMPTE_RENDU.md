# Compte Rendu — Exercice 3 : Instrumenter une application Flask avec le SDK OTel

**Date :** 2026-06-10
**Auteur :** mqnguyen
**Durée effective :** ~45 min
**Section TP :** Fondamentaux

---

## Objectif

Construire une application Flask Python auto-instrumentée OpenTelemetry, la conteneuriser,
la charger dans kind, la déployer comme Deployment Kubernetes dans le namespace `default`,
et vérifier que les 3 signaux (traces, logs, métriques) arrivent dans Alloy avec
`service.name=demo`.

---

## Environnement

| Élément | Valeur |
|---|---|
| Cluster | kind `otel-lab` |
| Namespace app | `default` |
| Namespace Alloy | `observability` |
| Image applicative | `demo-otel:v1` (construite localement) |
| SDK OTel Python | `opentelemetry-distro` + `opentelemetry-instrumentation-flask` |
| SDK version | `1.42.1` / auto-instrumentation `0.63b1` |
| Endpoint OTLP | `http://alloy.observability.svc:4318` (HTTP/protobuf) |

---

## Arborescence du dossier

```
~/tp-observabilite/otel-alloy-ex03/
├── app/
│   ├── app.py              ← application Flask avec latence et erreurs simulées
│   ├── requirements.txt    ← dépendances Python + OTel
│   └── Dockerfile          ← image avec opentelemetry-instrument
└── deployment.yaml         ← Deployment + Service Kubernetes
```

---

## Concepts clés abordés

### Auto-instrumentation OpenTelemetry

L'auto-instrumentation OTel permet d'instrumenter une application **sans modifier
son code source**. Le wrapper `opentelemetry-instrument` intercepte automatiquement :

- Toutes les requêtes HTTP entrantes → spans `GET /` avec méthode, route, status code
- Toutes les exceptions → events `exception` avec type, message et stacktrace
- Les logs applicatifs → forwarded vers le backend OTLP

La commande `opentelemetry-bootstrap -a install` détecte les bibliothèques installées
(Flask ici) et installe leurs instrumentations OTel correspondantes automatiquement.

### Variables d'environnement OTEL_*

Les variables `OTEL_*` configurent le SDK sans modifier le code :

| Variable | Valeur | Rôle |
|---|---|---|
| `OTEL_SERVICE_NAME` | `demo` | Nom du service dans les traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://alloy.observability.svc:4318` | Destination des signaux |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | Transport OTLP sur HTTP |
| `OTEL_LOGS_EXPORTER` | `otlp` | Active l'export des logs |
| `OTEL_METRICS_EXPORTER` | `otlp` | Active l'export des métriques |
| `OTEL_TRACES_EXPORTER` | `otlp` | Active l'export des traces |

### kind load docker-image

kind utilise des conteneurs Docker comme nœuds Kubernetes. Une image construite
localement sur la VM n'est **pas automatiquement disponible** dans le cluster.
La commande `kind load docker-image` copie l'image dans le registre interne de
chaque nœud kind. Sans cela, le pod tombe en `ImagePullBackOff`.

Le paramètre `imagePullPolicy: Never` dans le Deployment est indispensable : il
force Kubernetes à utiliser l'image locale sans tenter de la télécharger depuis
un registre externe.

---

## Fichiers créés

### app/app.py

```python
import random
import time
from flask import Flask

app = Flask(__name__)

@app.route("/")
def index():
    duration = random.uniform(0.01, 0.6)
    time.sleep(duration)
    if random.random() < 0.1:
        raise Exception("simulated error")
    return f"Hello from demo! (took {duration:.2f}s)\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

### app/requirements.txt

```
flask
opentelemetry-distro
opentelemetry-exporter-otlp
opentelemetry-instrumentation-flask
```

### app/Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    opentelemetry-bootstrap -a install

COPY app.py .

CMD ["opentelemetry-instrument", "python", "app.py"]
```

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
        - name: demo
          image: demo-otel:v1
          imagePullPolicy: Never
          ports:
            - containerPort: 5000
          env:
            - name: OTEL_SERVICE_NAME
              value: "demo"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://alloy.observability.svc:4318"
            - name: OTEL_EXPORTER_OTLP_PROTOCOL
              value: "http/protobuf"
            - name: OTEL_LOGS_EXPORTER
              value: "otlp"
            - name: OTEL_METRICS_EXPORTER
              value: "otlp"
            - name: OTEL_TRACES_EXPORTER
              value: "otlp"
---
apiVersion: v1
kind: Service
metadata:
  name: demo
  namespace: default
spec:
  selector:
    app: demo
  ports:
    - port: 5000
      targetPort: 5000
```

---

## Commandes exécutées

### 1. Construction de l'image Docker

```bash
docker build -t demo-otel:v1 app/
docker images | grep demo-otel
```

### 2. Chargement de l'image dans kind

```bash
kind load docker-image demo-otel:v1 --name otel-lab
```

### 3. Déploiement dans Kubernetes

```bash
kubectl apply -f deployment.yaml
kubectl get pods -w
```

### 4. Génération de trafic

```bash
kubectl port-forward svc/demo 5000:5000 &
sleep 2
for i in $(seq 1 30); do curl -s http://localhost:5000/ > /dev/null; done
```

### 5. Vérification dans les logs Alloy

```bash
kubectl -n observability logs daemonset/alloy --tail=300 | \
  grep -E "service.name|GET /|simulated" | head -20
```

---

## Résultats observés

### Pod applicatif

```
NAME          READY   STATUS    RESTARTS   AGE
demo-xxxxx    1/1     Running   0          Xm
```

### Signaux reçus dans Alloy

| Signal | Reçu | Détail |
|---|---|---|
| **Traces** | ✅ | Spans `GET /` avec `http.status_code`, durées variables (0.01s → 0.6s) |
| **Logs** | ✅ | Requêtes `200` et `500`, logs werkzeug, exceptions avec stacktrace |
| **Erreurs** | ✅ | `Status code: Error`, `exception.message: simulated error` avec stacktrace complète |

### Extrait trace avec erreur (service.name=demo)

```
ResourceSpans #0
Resource attributes:
  -> telemetry.sdk.language: Str(python)
  -> telemetry.sdk.name: Str(opentelemetry)
  -> telemetry.sdk.version: Str(1.42.1)
  -> service.name: Str(demo)
  -> telemetry.auto.version: Str(0.63b1)
Span #0
  Name           : GET /
  Kind           : Server
  Status code    : Error
  Status message : Exception: simulated error
  Attributes:
    -> http.method: Str(GET)
    -> http.status_code: Int(500)
    -> http.route: Str(/)
  SpanEvent #0
    -> Name: exception
    -> exception.type: Str(Exception)
    -> exception.message: Str(simulated error)
```

### Extrait log avec erreur (service.name=demo)

```
ResourceLog #0
Resource attributes:
  -> service.name: Str(demo)
ScopeLogs InstrumentationScope app
LogRecord #0
  SeverityText: ERROR
  Body: Str(Exception on / [GET])
  -> exception.type: Str(Exception)
  -> exception.message: Str(simulated error)
  -> exception.stacktrace: Str(Traceback...)
  Trace ID: 9bb43e799e4447fee660c7e1d77b6839
  Span ID:  63cd7a32755f8c2a
```

> Point remarquable : le log d'erreur porte les mêmes `Trace ID` et `Span ID`
> que la trace — c'est la **corrélation logs/traces** en action.

---

## Point clé : corrélation logs ↔ traces

L'un des apports majeurs d'OpenTelemetry est la **corrélation automatique** entre
les signaux. Quand une exception survient sur une requête, l'auto-instrumentation
Flask injecte le `trace_id` et le `span_id` courants dans le log d'erreur.

Cela permet, dans Grafana, de passer directement d'un log d'erreur à la trace
complète de la requête qui l'a générée — sans aucun code supplémentaire.

---

## Conclusion

L'application Flask est déployée et instrumente automatiquement tous ses signaux
vers Alloy grâce au wrapper `opentelemetry-instrument` et aux variables `OTEL_*`.

**Points clés retenus :**

- `opentelemetry-bootstrap -a install` détecte et installe les instrumentations adaptées aux bibliothèques présentes
- `opentelemetry-instrument` active l'auto-instrumentation sans modification du code applicatif
- `kind load docker-image` + `imagePullPolicy: Never` sont indispensables pour les images locales dans kind
- L'auto-instrumentation capture automatiquement méthode HTTP, status code, durée et exceptions
- Les logs d'erreur portent le `trace_id` de la requête, permettant la corrélation logs ↔ traces

L'exercice 4 portera sur l'extension du pipeline Alloy avec des processors
(batch + ajout d'attributs) et le hot reload sans redémarrage.
