FROM nginx:latest

ARG VAULT_VERSION=1.12.0
ARG VAULTBOT_VERSION=1.14.3


RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq \
        unzip \
        ca-certificates \
        procps \
        openssl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip \
    && unzip /tmp/vault.zip -d /usr/local/bin \
    && rm /tmp/vault.zip \
    && chmod +x /usr/local/bin/vault

# Download official Vaultbot binary release
RUN curl -fsSL "https://github.com/soundcloud/vault-bot/releases/download/v${VAULTBOT_VERSION}/vaultbot_${VAULTBOT_VERSION}_linux_amd64.tar.gz" -o /tmp/vaultbot.tar.gz \
    && tar -xf /tmp/vaultbot.tar.gz -C /usr/local/bin vaultbot \
    && rm /tmp/vaultbot.tar.gz \
    && chmod +x /usr/local/bin/vaultbot

COPY nginx.conf /etc/nginx/nginx.conf
COPY html/ /usr/share/nginx/html/
COPY run.sh /usr/local/bin/run-nginx-bot.sh
COPY vault-bot.sh /usr/local/bin/vault-bot.sh
COPY vaultbot-renew-hook.sh /usr/local/bin/vaultbot-renew-hook.sh

RUN chmod +x /usr/local/bin/run-nginx-bot.sh /usr/local/bin/vault-bot.sh /usr/local/bin/vaultbot-renew-hook.sh \
    && mkdir -p /etc/nginx/certs \
    && openssl req -x509 -nodes -newkey rsa:2048 \
         -keyout /etc/nginx/certs/key.pem \
         -out /etc/nginx/certs/cert.pem \
         -days 1 \
         -subj "/CN=placeholder.local" \
    && cp /etc/nginx/certs/cert.pem /etc/nginx/certs/ca.pem

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/run-nginx-bot.sh"]
