# ---------- Builder ----------
FROM node:20-alpine AS builder

# Paquetes necesarios para scripts y build
RUN apk update && apk add --no-cache \
  git ffmpeg wget curl bash openssl dos2unix

LABEL version="2.3.1" description="Api to control whatsapp features through http requests."
LABEL maintainer="Davidson Gomes" git="https://github.com/DavidsonGomes"
LABEL contact="contato@evolution-api.com"

WORKDIR /evolution

# Copiamos metadatos primero para aprovechar la cache
COPY ./package*.json ./ 
COPY ./tsconfig.json ./ 
COPY ./tsup.config.ts ./

# Forzar resolución de peer deps (conflicto baileys <-> jimp)
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true
# Si existe package-lock.json, usa ci; si no, install
# (Fly usará la capa cacheada cuando no cambien deps)
RUN if [ -f package-lock.json ]; then npm ci --legacy-peer-deps --silent; else npm i --legacy-peer-deps --silent; fi

# Resto del código
COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./Docker ./Docker

# Normalizar fin de línea de scripts y dar permisos
RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/*

# DB local (sqlite) y build de la app
RUN ./Docker/scripts/generate_database.sh
RUN npm run build

# ---------- Runtime ----------
FROM node:20-alpine AS final

RUN apk update && apk add --no-cache tzdata ffmpeg bash openssl

ENV TZ=America/Sao_Paulo
ENV DOCKER_ENV=true

WORKDIR /evolution

# Copiamos artefactos del builder
COPY --from=builder /evolution/package.json ./package.json
COPY --from=builder /evolution/package-lock.json ./package-lock.json
COPY --from=builder /evolution/node_modules ./node_modules
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/.env ./.env
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

# Puerto interno
EXPOSE 8080

# Despliega DB (sqlite) y arranca
ENTRYPOINT ["/bin/bash", "-c", ". ./Docker/scripts/deploy_database.sh && npm run start:prod" ]
