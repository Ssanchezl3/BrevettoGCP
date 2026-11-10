# Despliegue de Brevetto en Google Cloud (Compute Engine)

Guía paso a paso para publicar Brevetto en internet con HTTPS. Toma unos 30 minutos la primera vez.

## Arquitectura del despliegue

Una sola máquina virtual corre todos los servicios con Docker Compose (`docker-compose.prod.yml`). Solo el
proxy **Caddy** expone puertos (80 y 443) y obtiene el certificado HTTPS de Let's Encrypt automáticamente.

```text
Internet ──HTTPS──► Caddy :443 ──┬── /api/*, /django-admin/*, /static/*  ► backend (Django + Gunicorn)
                                 ├── /brevetto-docs/*                    ► MinIO (descarga de documentos)
                                 └── todo lo demás                       ► frontend (Next.js)

backend ──► PostgreSQL 16 · Redis 7 · MinIO        celery_worker ──► Redis · Gemini API
```

PostgreSQL, Redis y MinIO no quedan expuestos a internet: solo se alcanzan dentro de la red de Docker.
Los datos persisten en volúmenes de Docker (`postgres_data`, `minio_data`, `redis_data`, `caddy_data`).

## 1. Crear la máquina virtual

En la consola de GCP (**Compute Engine → Instancias de VM → Crear instancia**):

| Campo | Valor recomendado |
|---|---|
| Nombre | `brevetto` |
| Región | `us-east1` (o `southamerica-east1`, São Paulo) |
| Tipo de máquina | `e2-medium` (2 vCPU, 4 GB). `e2-small` alcanza para la demo si se crea swap |
| Disco de arranque | Ubuntu 24.04 LTS, 30 GB |
| Firewall | Marcar **Permitir tráfico HTTP** y **Permitir tráfico HTTPS** |

Luego reserve una IP fija: **Red de VPC → Direcciones IP → Reservar dirección estática externa** y asígnela a
la VM. Anote la IP (ejemplo: `34.120.45.67`).

> Con `gcloud` el equivalente es:
> ```bash
> gcloud compute addresses create brevetto-ip --region=us-east1
> gcloud compute instances create brevetto --zone=us-east1-b --machine-type=e2-medium \
>   --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=30GB \
>   --tags=http-server,https-server --address=brevetto-ip
> gcloud compute firewall-rules create allow-http-https --allow=tcp:80,tcp:443 --target-tags=http-server,https-server
> ```

## 2. Elegir el dominio

- **Sin dominio propio (recomendado para la sustentación):** use `sslip.io`, que resuelve cualquier IP gratis.
  Con la IP `34.120.45.67` el dominio es **`34-120-45-67.sslip.io`**. Let's Encrypt emite el certificado normal.
- **Con dominio propio:** cree un registro `A` que apunte a la IP de la VM y espere a que propague.

## 3. Preparar la VM

Entre por SSH (botón **SSH** en la consola) y ejecute:

```bash
git clone https://github.com/Ssanchezl3/BrevettoGCP.git
cd BrevettoGCP
bash deploy/setup-vm.sh      # instala Docker y crea swap
exit                         # salga y vuelva a entrar por SSH para usar docker sin sudo
```

## 4. Configurar las variables

```bash
cd BrevettoGCP
cp deploy/.env.prod.example .env.prod
nano .env.prod
```

Complete como mínimo:

| Variable | Qué poner |
|---|---|
| `BREVETTO_DOMAIN` | El dominio del paso 2, sin `https://` |
| `DJANGO_SECRET_KEY` | Valor aleatorio: `openssl rand -base64 48 \| tr -d '\n/+='` |
| `POSTGRES_PASSWORD`, `MINIO_ROOT_PASSWORD` | Contraseñas largas distintas |
| `GEMINI_API_KEY` | Clave de https://aistudio.google.com/apikey (sin ella todo va a revisión humana) |
| `EMAIL_*` | Opcional: SMTP para enviar códigos de acceso y avisos a los clientes |
| `CLIENT_OTP_DEV_ECHO` | `True` para la demo (el código aparece en pantalla); `False` con SMTP real |

`.env.prod` está en `.gitignore`. No lo suba al repositorio ni lo comparta por chat.

## 5. Levantar Brevetto

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
```

La primera compilación tarda de 5 a 10 minutos. El backend aplica las migraciones y crea el bucket al
arrancar. Cuando todos los servicios estén `running`/`healthy`, abra `https://<BREVETTO_DOMAIN>`.

## 6. Crear usuarios y datos de demostración

```bash
alias dc='docker compose -f docker-compose.prod.yml --env-file .env.prod'
dc exec backend python manage.py createsuperuser          # administrador (admin de Django)
dc exec backend python manage.py seed_demo_data           # usuario demo / Brevetto2026!, contratos y documentos
dc exec backend python manage.py seed_client_portal_demo  # cliente de Mi Portal (NIT 900.845.112-3)
```

`seed_demo_data` crea datos ficticios para la demostración. En un despliegue real para Coltebienes no se ejecuta.

## 7. Verificar

| Prueba | Resultado esperado |
|---|---|
| `curl https://<dominio>/api/v1/health/` | `{"status": "ok", "service": "brevetto-backend"}` |
| `https://<dominio>/` | Página de inicio con el candado HTTPS |
| `https://<dominio>/login/empleados` con `demo` | Panel del personal |
| Abrir un documento en un expediente | El PDF se ve (prueba la ruta de MinIO por Caddy) |
| `https://<dominio>/django-admin/` | Admin de Django con estilos |
| `https://<dominio>/ayuda` | Manual de usuario |

## Operación

```bash
dc logs -f backend celery_worker          # ver logs
dc pull && git pull && dc up -d --build   # actualizar a la última versión del repositorio
dc restart backend                        # reiniciar un servicio
```

**Copia de seguridad de la base de datos:**

```bash
dc exec -T db pg_dump -U brevetto brevetto | gzip > backup_$(date +%F).sql.gz
# restaurar: gunzip -c backup_AAAA-MM-DD.sql.gz | dc exec -T db psql -U brevetto brevetto
```

Los documentos están en el volumen `brevetto-prod_minio_data`. En GCP se puede programar una instantánea
diaria del disco de la VM (**Compute Engine → Instantáneas → Crear programación**), que cubre base de datos y archivos.

## Apagar y encender la VM (ahorro de créditos)

La VM cobra cómputo **solo mientras está encendida**. Cuando no se use (por ejemplo entre sustentaciones),
conviene apagarla. Los contenedores tienen `restart: unless-stopped`, así que **arrancan solos** al encender
de nuevo; no hay que repetir ningún paso de instalación.

```bash
# Apagar (deja de cobrar cómputo)
gcloud compute instances stop brevetto --zone=us-east1-b

# Encender de nuevo (Brevetto vuelve a estar disponible en el mismo dominio en 1-2 min)
gcloud compute instances start brevetto --zone=us-east1-b

# Ver si está encendida o apagada
gcloud compute instances describe brevetto --zone=us-east1-b --format="value(status)"
```

Notas:
- La **IP estática** reservada se conserva al apagar/encender, por lo que el dominio `sslip.io` no cambia.
- Mientras la VM está apagada, la IP estática reservada y el disco siguen cobrando un valor muy pequeño.
  Para no pagar nada hay que liberar esos recursos (ver más abajo).

### Borrar todo (dejar de pagar por completo)

```bash
gcloud compute instances delete brevetto --zone=us-east1-b   # borra la VM y su disco
gcloud compute addresses delete brevetto-ip --region=us-east1 # libera la IP estática
```

> Esto elimina también los datos (base de datos y documentos). Haga una copia de seguridad antes si los necesita.

## Consultar créditos y gasto

El **saldo de créditos** solo se ve de forma fiable en la consola web:
**[console.cloud.google.com/billing](https://console.cloud.google.com/billing)** → la cuenta de facturación →
**Credits** (saldo y fecha de expiración) y **Reports** (gasto por proyecto). `gcloud` no expone el saldo de
créditos; `gcloud billing projects describe brevetto-prod` solo confirma que la facturación está vinculada.

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| El navegador no abre HTTPS / error de certificado | Puertos 80/443 cerrados en el firewall, o el dominio no apunta a la IP. Revise `dc logs caddy`. |
| `Bad Request (400)` | `BREVETTO_DOMAIN` no coincide con la URL que se usa. Corríjalo y ejecute `dc up -d`. |
| Los PDF no se ven pero la API responde | Cambió `AWS_STORAGE_BUCKET_NAME` sin reiniciar Caddy, o `BREVETTO_DOMAIN` tiene `https://`. |
| Documentos quedan en "Requiere revisión" | Falta `GEMINI_API_KEY` o la clave venció: es el comportamiento esperado (revisión humana). |
| La compilación del frontend se cae por memoria | Ejecute `deploy/setup-vm.sh` (crea swap) o use `e2-medium`. |
| `401 UNAUTHORIZED` al descargar la imagen de MinIO | MinIO archivó sus imágenes oficiales. El proyecto usa el fork `docker.io/pgsty/silo`; si su copia del repo aún apunta a `quay.io/minio/minio`, haga `git pull`. |

## Costo aproximado

Una `e2-medium` encendida todo el mes cuesta del orden de USD 25–30 más el disco y la IP estática; una `e2-small`,
cerca de la mitad. Los créditos gratuitos de GCP para estudiantes o de prueba cubren la demostración.
Apague la VM cuando no se use (la IP estática reservada sigue cobrando un valor bajo).
