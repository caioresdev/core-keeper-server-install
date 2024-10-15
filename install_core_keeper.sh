#!/bin/bash

# Função para perguntar e capturar resposta do usuário
function perguntar() {
    local mensagem="$1"
    local padrao="$2"
    read -p "$mensagem [Padrão: $padrao]: " resposta
    echo "${resposta:-$padrao}"
}

# 1° Passo: Perguntar se deseja prosseguir
read -p "Deseja fazer a instalação do servidor dedicado do Core Keeper? (s/N): " resposta
if [[ ! "$resposta" =~ ^[sS]$ ]]; then
    echo "Instalação cancelada pelo usuário."
    exit 0
fi

# 2° Passo: Perguntas para preencher o core.env
mkdir -p server-files server-data
cat > core.env <<EOL
WORLD_INDEX=$(perguntar "Qual o índice do mundo?" "0")
WORLD_NAME=$(perguntar "Nome do servidor?" "MeuServidorCoreKeeper")
WORLD_SEED=$(perguntar "Seed para o novo mundo? (Digite 0 para gerar automaticamente)" "0")
WORLD_MODE=$(perguntar "Modo do mundo (0: Normal, 1: Hard, 2: Creative, 4: Casual)?" "0")
GAME_ID=$(perguntar "ID do Jogo (mínimo 28 caracteres alfanuméricos)?" "")
DATA_PATH=$(perguntar "Local de salvamento dos arquivos?" "./server-data")
MAX_PLAYERS=$(perguntar "Número máximo de jogadores?" "8")
DISCORD=$(perguntar "Deseja habilitar integração com Discord (s/N)?" "N")
DISCORD_HOOK=$(perguntar "URL do Webhook do Discord (se aplicável)?" "")
DISCORD_PRINTF_STR=$(perguntar "Formato do Webhook do Discord?" "%s")
SEASON=$(perguntar "Estação atual (0: Nenhuma, 1: Páscoa, etc.)?" "0")
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_PORT=$(perguntar "Porta do servidor?" "4390")
EOL

# 3° Passo: Configurações padrão
if [ -z "$GAME_ID" ]; then
    GAME_ID="CK_$(date +%s)_ID_AUTOMATICO"
    echo "GAME_ID=$GAME_ID" >> core.env
fi

# 4° Passo: Verificar se Docker, Podman e Docker Compose estão instalados
if ! command -v docker &> /dev/null && ! command -v podman &> /dev/null; then
    echo "Docker ou Podman não encontrado. Instalando Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo groupadd docker
    sudo usermod -aG docker $USER
    echo "Por favor, saia e entre novamente na sessão para aplicar as permissões do grupo Docker."
fi

if ! command -v docker-compose &> /dev/null && ! command -v podman-compose &> /dev/null; then
    echo "Docker Compose ou Podman Compose não encontrado. Instalando Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Garantir que o Docker Daemon está em execução
if command -v docker &> /dev/null; then
    echo "Verificando se o Docker Daemon está em execução..."
    if ! pgrep -x "dockerd" > /dev/null; then
        echo "Iniciando Docker Daemon manualmente..."
        sudo dockerd > /dev/null 2>&1 &
        sleep 5
        if ! pgrep -x "dockerd" > /dev/null; then
            echo "Erro: Docker Daemon não pôde ser iniciado. Verifique manualmente o estado do Docker."
            exit 1
        fi
    fi
fi

# Criar o docker-compose.yaml
cat > docker-compose.yaml <<EOL
version: "3"

services:
  core-keeper:
    container_name: corekeeperserver
    image: arguser/core-keeper-dedicated
    volumes:
      - ./server-files:/home/steam/core-keeper-dedicated
      - ./server-data:/home/steam/core-keeper-data
    env_file:
      - ./core.env
    ports:
      - "${SERVER_PORT}:${SERVER_PORT}"
    restart: always
    stop_grace_period: 1m
EOL

# 5° Passo: Perguntar se deseja definir limites de recursos
read -p "Deseja definir limites de 2 CPU e 4GB de RAM para o container? (s/N): " resposta_limites
if [[ "$resposta_limites" =~ ^[sS]$ ]]; then
    sed -i '/stop_grace_period: 1m/a\    deploy:\n      resources:\n        limits:\n          cpus: "2"\n          memory: "4g"' docker-compose.yaml
fi

# Executar o container
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
elif command -v podman-compose &> /dev/null; then
    podman-compose up -d
else
    echo "Nenhum gerenciador de containers (Docker Compose ou Podman Compose) disponível para iniciar o container."
    exit 1
fi

# Provável falha inicial do container e ajuste de permissões
if command -v docker &> /dev/null; then
    docker stop corekeeperserver
    sudo chmod 777 ./server-files -R
    sudo chmod 777 ./server-data -R
    docker start corekeeperserver
    docker exec -it -u=root corekeeperserver bash -c "apt update && apt install -y libxi6"
    docker restart corekeeperserver
elif command -v podman &> /dev/null; then
    podman stop corekeeperserver
    sudo chmod 777 ./server-files -R
    sudo chmod 777 ./server-data -R
    podman start corekeeperserver
    podman exec -it -u=root corekeeperserver bash -c "apt update && apt install -y libxi6"
    podman restart corekeeperserver
fi

# Mostrar mensagem final
if command -v docker &> /dev/null; then
    game_id_log=$(docker logs corekeeperserver 2>&1 | grep "Game ID" | tail -n 1)
    if [ -n "$game_id_log" ]; then
        echo "Instalação finalizada! O ID do jogo é: ${game_id_log}"
    else
        echo "Instalação finalizada! Não foi possível encontrar o ID do jogo nos logs. Verifique os logs manualmente."
    fi
elif command -v podman &> /dev/null; then
    game_id_log=$(podman logs corekeeperserver 2>&1 | grep "Game ID" | tail -n 1)
    if [ -n "$game_id_log" ]; then
        echo "Instalação finalizada! O ID do jogo é: ${game_id_log}"
    else
        echo "Instalação finalizada! Não foi possível encontrar o ID do jogo nos logs. Verifique os logs manualmente."
    fi
fi

echo "Obrigado por utilizar o instalador do servidor dedicado do Core Keeper!"