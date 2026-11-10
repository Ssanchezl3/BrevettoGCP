# 🏛️ Brevetto — Sistema Inteligente de Gestión Documental

Plataforma inteligente de automatización, radicación, clasificación asistida por IA y consulta de expedientes digitales para **Coltebienes S.A.**

## 🌐 Aplicación desplegada

| | |
| :--- | :--- |
| **URL pública** | **https://35-237-79-146.sslip.io** |
| Manual de usuario | https://35-237-79-146.sslip.io/ayuda (también enlazado desde la app) |
| Nube | Google Cloud Platform · Compute Engine (Docker Compose + Caddy con HTTPS automático) |
| Guía de despliegue | [Despliegue en GCP](#-despliegue-en-google-cloud-gcp) · guía completa en [`deploy/README.md`](deploy/README.md) |
| Wiki del proyecto | https://github.com/Ssanchezl3/BrevettoGCP/wiki |

Usuarios de demostración (datos ficticios de `seed_demo_data`): personal `demo` / `Brevetto2026!` en **Acceso
empleados**; cliente NIT `900.845.112-3` en **Mi Portal** (el código de acceso se muestra en pantalla en modo demo).

---

## 🚀 Arquitectura y Tecnologías
- **Frontend:** Next.js (App Router), React, TypeScript.
- **Backend:** Python 3.11+, Django 5, Django REST Framework, Celery 5.
- **Base de Datos:** PostgreSQL 16.
- **Broker & Queue:** Redis 7.
- **Almacenamiento de Objetos:** AWS S3 / MinIO.
- **Motor de Inteligencia Artificial:** Google Gemini API (Multimodal OCR & Clasificación).
- **Contenedores:** Docker & Docker Compose.
---

## 📖 Documentación del Proyecto
La documentación funcional, de pruebas, el caso de negocio y las evidencias de cada sprint viven en la
**[wiki del proyecto](https://github.com/Ssanchezl3/BrevettoGCP/wiki)**. En el repositorio quedan:

* [`deploy/README.md`](deploy/README.md): despliegue en Google Cloud paso a paso, operación y copias de seguridad.
* [`CHANGELOG.md`](CHANGELOG.md): cambios por versión.
* [`e2e/`](e2e/): pruebas de extremo a extremo en navegador (Playwright).
* Manual de usuario: integrado en la aplicación en la ruta `/ayuda`.

---

## ⚡ Comandos de Inicio Rápido

### 1. Iniciar los servicios con Docker:
```bash
docker compose up -d --build
```

### 2. Ejecutar migraciones de base de datos:
```bash
docker compose exec backend python manage.py migrate
```

### 3. Ejecutar la suite de pruebas del backend (requiere el contenedor `db` activo):
```bash
docker compose up -d db redis minio
cd backend
uv venv .venv --python 3.12 && uv pip install --python .venv/Scripts/python.exe -r requirements.txt
POSTGRES_HOST=localhost .venv/Scripts/python.exe -m pytest -v
```

Calidad del código (mismas verificaciones que el CI):
```bash
cd backend && uv pip install --python .venv/Scripts/python.exe -r requirements-dev.txt
.venv/Scripts/python.exe -m ruff check . && .venv/Scripts/python.exe -m ruff format --check .
.venv/Scripts/python.exe -m mypy apps config
POSTGRES_HOST=localhost .venv/Scripts/python.exe -m pytest --cov=apps
```

Pruebas de extremo a extremo (navegador), con la aplicación levantada y los datos de demostración:
```bash
cd e2e && npm install && npx playwright install chromium
BREVETTO_URL=http://localhost:3000 npm test      # o https://localhost con docker-compose.prod.yml
```

### 4. Servicios y puertos del entorno local

| Servicio | URL / Puerto | Credenciales dev (.env.example) |
| :--- | :--- | :--- |
| API Django | http://localhost:8000/api/v1/health/ | JWT en `/api/v1/auth/token/` |
| Admin Django | http://localhost:8000/admin/ (en producción: `/django-admin/`) | crear con `manage.py createsuperuser` |
| Frontend Next.js | http://localhost:3000 | — |
| PostgreSQL 16 | localhost:5432 | brevetto / brevetto |
| Redis 7 | localhost:6379 | — |
| MinIO API / Consola | http://localhost:9000 / http://localhost:9001 | minioadmin / minioadmin |

> El almacenamiento de objetos usa `docker.io/pgsty/silo` (fork community compatible con la API S3 de MinIO):
> MinIO archivó sus imágenes oficiales y en septiembre de 2026 dejaron de poder descargarse desde Docker Hub y quay.io.

### 5. Endpoints implementados (Sprint 1, autenticación JWT `Authorization: Bearer <token>`)

| Método | Ruta | Descripción |
| :--- | :--- | :--- |
| POST | `/api/v1/auth/token/` | Obtiene access/refresh JWT |
| POST | `/api/v1/documents/upload/` | Radica un documento (multipart) y encola el análisis IA |
| POST | `/api/v1/documents/batch-upload/` | Radica varios documentos en un envío (202) |
| GET | `/api/v1/documents/` · `/{id}/` | Listado paginado con filtros/búsqueda y detalle |
| GET | `/api/v1/documents/pending-review/` | Bandeja Human-in-the-Loop (`REQUIERE_REVISION`) |
| POST | `/api/v1/documents/{id}/validate/` | Confirmación humana: asocia contrato y tipo, archiva |
| PATCH | `/api/v1/documents/{id}/metadata/` | Actualiza metadatos con antes/después en `AuditLog` |
| GET | `/api/v1/documents/{id}/view-url/` · `download-url/` | URL prefirmada (15 min) + registro de consulta/descarga |
| GET | `/api/v1/documents/{id}/audit-trail/` | Historial inmutable del documento |
| GET/POST/PATCH | `/api/v1/contracts/` | Contratos; al crear se genera expediente y carpeta en S3 |
| GET | `/api/v1/contracts/{id}/documents/` · `audit-trail/` | Expediente digital y su historial |
| GET/POST/PATCH | `/api/v1/clients/` | Clientes (sin DELETE: integridad referencial) |
| GET | `/api/v1/document-types/` | Catálogo documental sembrado por migración |

Pipeline IA: `documents.process_document_content` (Celery) descarga el archivo de MinIO, consulta Gemini con salida JSON estructurada y aplica la regla HITL (`AI_CONFIDENCE_THRESHOLD=0.85`). Sin `GEMINI_API_KEY` el documento pasa directamente a revisión manual.

### 6. Interfaces web (Fase 5)

| Ruta | Descripción |
| :--- | :--- |
| `/login` | Ingreso del personal (JWT) |
| `/admin` | Bandeja de ingesta en tiempo real: contadores por estado, búsqueda, filtros y sondeo cada 5 s |
| `/admin/upload` | Radicación individual o por lote con arrastrar-y-soltar y contrato opcional |
| `/admin/review` · `/admin/review/{id}` | Bandeja HITL y validación en pantalla dividida (visor PDF + sugerencias IA + formulario) |
| `/admin/documents/{id}` | Ficha del documento, edición de metadatos, descarga segura e historial de auditoría |
| `/admin/contracts` · `/admin/contracts/{id}` | Contratos, alta con cliente nuevo o existente, expediente agrupado por categoría y auditoría |
| `/portal/radicacion` | Portal público del inquilino: valida contrato + NIT, radica y descarga/imprime el comprobante |
| `/admin/requerimientos` · `/admin/requerimientos/{id}` | Atención de requerimientos de clientes: estados, asesor, solución, chat y adjuntos |
| `/admin/audit` | Auditoría global inmutable con filtros |
| `/login`, `/portal/*` | Mi Portal del cliente: contrato, documentos, radicación y requerimientos |
| `/ayuda` | Manual de usuario para clientes y personal |

API del portal público (sin JWT, con throttling y token temporal firmado de 30 min):
`POST /api/v1/portal/verify-contract/` y `POST /api/v1/portal/submit-document/`.

**Modelos Gemini:** `gemini-1.5-flash` y la familia 2.x fueron retirados. Por defecto se usa `gemini-3.5-flash` con
respaldo inmediato en `gemini-3-flash-preview` ante 503/429 (`GEMINI_FALLBACK_MODEL`). La prueba de integración real se
ejecuta con `BREVETTO_RUN_INTEGRATION=1 ... pytest -m integration`.

**Resiliencia del pipeline:** la tarea reintenta 3 veces con backoff ante fallos transitorios, Celery restaura los mensajes no confirmados al reiniciar el worker (`acks_late`), y el worker corre Celery beat (`-B`) con `documents.requeue_stale_documents`, que cada 5 minutos re-encola documentos sin avance en `RECIBIDO`/`PROCESANDO` durante más de 15 minutos (`PROCESSING_STALE_AFTER_MINUTES`).

---

## ☁️ Despliegue en Google Cloud (GCP)

Brevetto se despliega en **una sola máquina virtual de Compute Engine** con Docker Compose. Solo el proxy
**Caddy** expone los puertos 80/443 y obtiene el certificado **HTTPS automáticamente** (Let's Encrypt).
PostgreSQL, Redis y MinIO quedan en la red interna de Docker y no se exponen a internet.

```text
Internet ──HTTPS──► Caddy :443 ──┬── /api/*, /django-admin/*, /static/*  ► backend (Django + Gunicorn)
                                 ├── /brevetto-docs/*                    ► MinIO (descarga de documentos)
                                 └── todo lo demás                       ► frontend (Next.js)
```

> 📘 La guía detallada (creación de la VM con `gcloud`, dominio, operación, copias de seguridad y solución de
> problemas) está en **[`deploy/README.md`](deploy/README.md)**. Lo que sigue es el resumen operativo.

### Requisitos previos
- Proyecto de GCP con facturación activa y la CLI `gcloud` (o la consola web).
- Clave de **Google Gemini** (opcional). Sin ella, todos los documentos pasan directo a revisión humana.
- Un dominio. Si no tienes uno, usa **sslip.io** con la IP de la VM (ej.: IP `34.120.45.67` → `34-120-45-67.sslip.io`).

### Paso 1 — Crear la VM con IP estática y firewall HTTP/HTTPS
```bash
gcloud compute addresses create brevetto-ip --region=us-east1
gcloud compute instances create brevetto --zone=us-east1-b --machine-type=e2-medium \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=30GB \
  --tags=http-server,https-server --address=brevetto-ip
gcloud compute firewall-rules create allow-http-https --allow=tcp:80,tcp:443 \
  --target-tags=http-server,https-server
```
Recomendado `e2-medium` (2 vCPU, 4 GB). Con `e2-small` crea swap (lo hace `setup-vm.sh`).

### Paso 2 — Preparar la VM (por SSH)
```bash
git clone https://github.com/Ssanchezl3/BrevettoGCP.git
cd BrevettoGCP
bash deploy/setup-vm.sh     # instala Docker + plugin Compose y crea 2 GB de swap
exit                        # vuelve a entrar por SSH para usar docker sin sudo
```

### Paso 3 — Configurar las variables de producción
```bash
cd BrevettoGCP
cp deploy/.env.prod.example .env.prod
nano .env.prod
```

| Variable | Qué poner |
| :--- | :--- |
| `BREVETTO_DOMAIN` | El dominio del paso previo, **sin** `https://` ni barra final |
| `DJANGO_SECRET_KEY` | Valor aleatorio: `openssl rand -base64 48 \| tr -d '\n/+='` |
| `POSTGRES_PASSWORD`, `MINIO_ROOT_PASSWORD` | Contraseñas largas y distintas |
| `GEMINI_API_KEY` | Clave de https://aistudio.google.com/apikey (opcional) |
| `EMAIL_*` | Opcional: SMTP para códigos de acceso y avisos a clientes |
| `CLIENT_OTP_DEV_ECHO` | `True` para la demo (muestra el código en pantalla); `False` con SMTP real |

> `.env.prod` está en `.gitignore`: nunca lo subas al repositorio ni lo compartas.

### Paso 4 — Levantar la plataforma
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
```
La primera compilación tarda de 5 a 10 minutos. El contenedor `backend` **aplica las migraciones y crea el
bucket automáticamente** al arrancar (`entrypoint.sh`). Cuando todo esté `running`/`healthy`, abre
`https://<BREVETTO_DOMAIN>`.

### Paso 5 — Crear usuarios y (opcional) datos de demostración
```bash
alias dc='docker compose -f docker-compose.prod.yml --env-file .env.prod'
dc exec backend python manage.py createsuperuser          # administrador (admin de Django)
dc exec backend python manage.py seed_demo_data           # demo / Brevetto2026! + contratos y documentos
dc exec backend python manage.py seed_client_portal_demo  # cliente de Mi Portal (NIT 900.845.112-3)
```
En un despliegue real para Coltebienes, **omite los comandos `seed_*`** (solo cargan datos ficticios).

### Paso 6 — Verificar
| Prueba | Resultado esperado |
| :--- | :--- |
| `curl https://<dominio>/api/v1/health/` | `{"status": "ok", "service": "brevetto-backend"}` |
| `https://<dominio>/` | Página de inicio con el candado HTTPS |
| Abrir un documento de un expediente | El PDF se visualiza (valida la ruta de MinIO vía Caddy) |
| `https://<dominio>/django-admin/` | Admin de Django con estilos |

### Paso 7 — Entrar a la aplicación
Con los datos de demostración cargados (Paso 5):

| Rol | Ruta | Credenciales |
| :--- | :--- | :--- |
| **Personal** | `/login/empleados` | usuario `demo` · contraseña `Brevetto2026!` |
| **Cliente (Mi Portal)** | `/login` | tipo **NIT**, número `900.845.112-3` → pide el código; en modo demo **aparece en pantalla**. Úsalo de inmediato (solo hay un código activo a la vez). |
| **Radicación pública** | `/portal/radicacion` | contrato `CONT-2025-018` + NIT `900.845.112-3` |

---

## 🔌 Prender y apagar la app

La VM **cobra cómputo solo mientras está encendida**. Apágala cuando no la uses para ahorrar créditos; los
contenedores tienen `restart: unless-stopped`, así que **arrancan solos** al encender de nuevo (no hay que
repetir ningún paso). Estos comandos se ejecutan **desde tu PC** (donde tienes `gcloud`):

```bash
# APAGAR la app (deja de cobrar cómputo)
gcloud compute instances stop brevetto --zone=us-east1-b

# PRENDER la app (vuelve a estar disponible en el mismo dominio en 1-2 min)
gcloud compute instances start brevetto --zone=us-east1-b

# Ver si está encendida (RUNNING) o apagada (TERMINATED)
gcloud compute instances describe brevetto --zone=us-east1-b --format="value(status)"
```

> 💡 La **IP estática** se conserva al apagar/encender, por lo que el dominio `sslip.io` no cambia.
> Mientras está apagada, la IP reservada y el disco cobran un valor mínimo. Para no pagar nada, hay que
> borrar los recursos (ver [`deploy/README.md`](deploy/README.md) → *Borrar todo*).

**Reiniciar solo los contenedores sin apagar la VM** (entra antes por `gcloud compute ssh brevetto --zone=us-east1-b && cd BrevettoGCP`):
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod restart   # reinicia todo
docker compose -f docker-compose.prod.yml --env-file .env.prod stop       # detiene los contenedores
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d       # vuelve a levantarlos
```

---

## 🛠️ Operación y mantenimiento

Dentro de la VM (`gcloud compute ssh brevetto --zone=us-east1-b && cd BrevettoGCP`), con el alias
`alias dc='docker compose -f docker-compose.prod.yml --env-file .env.prod'`:

```bash
dc ps                                      # estado de los servicios
dc logs -f backend celery_worker           # ver logs en vivo
git pull && dc up -d --build               # actualizar a la última versión del repositorio
dc exec -T db pg_dump -U brevetto brevetto | gzip > backup_$(date +%F).sql.gz   # respaldo de la BD
```

Los documentos viven en el volumen `brevetto-prod_minio_data`. En GCP puedes programar una **instantánea
diaria del disco** de la VM (cubre base de datos y archivos).

> **Nota sobre el almacenamiento:** el servicio `minio` usa el fork `docker.io/pgsty/silo` porque MinIO
> archivó sus imágenes oficiales (Docker Hub y quay.io dejaron de servirlas en 2026). Es un reemplazo
> compatible con la API S3 y no requiere cambios adicionales.

Más detalle (consulta de créditos, borrado total y solución de problemas) en [`deploy/README.md`](deploy/README.md).
