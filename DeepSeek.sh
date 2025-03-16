#!/bin/bash

# 定义程序目录
PROGRAM_DIR=$(dirname "$0")
DEPENDENCIES_DIR="$PROGRAM_DIR/dependencies"
JSON_PARSER="$DEPENDENCIES_DIR/jq"

# 创建依赖目录
mkdir -p "$DEPENDENCIES_DIR"

# 下载jq
download_jq() {
    if ! command -v "$JSON_PARSER" &> /dev/null; then
        echo "下载jq..."
        curl -L "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64" -o "$JSON_PARSER"
        chmod +x "$JSON_PARSER"
    fi
}

# 检查并下载依赖
download_jq
