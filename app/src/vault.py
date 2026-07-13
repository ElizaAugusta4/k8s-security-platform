"""
Lê segredos injetados pelo Vault Agent.
O Agent Injector escreve os segredos em /vault/secrets/config
antes do container principal subir.

Formato do arquivo injetado:
  APP_SECRET_KEY=valor
  DB_PASSWORD=valor
"""

import os


def load_vault_secrets() -> dict:
    """
    Lê o arquivo de segredos injetado pelo Vault Agent.
    Em desenvolvimento, usa variáveis de ambiente como fallback.
    """
    secrets = {}
    vault_file = "/vault/secrets/config"

    if os.path.exists(vault_file):
        with open(vault_file) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    secrets[key.strip()] = value.strip()
    else:
        # Fallback para desenvolvimento local
        secrets["APP_SECRET_KEY"] = os.getenv(
            "APP_SECRET_KEY", "dev-secret-key-nao-use-em-producao"
        )
        secrets["DB_PASSWORD"] = os.getenv("DB_PASSWORD", "dev-password")

    return secrets


SECRETS = load_vault_secrets()