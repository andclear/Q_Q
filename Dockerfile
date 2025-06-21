FROM ghcr.io/andclear/t_t:main

EXPOSE 6185
EXPOSE 8000

ENV BASE_URL=https://generativelanguage.googleapis.com/v1beta
ENV TOOLS_CODE_EXECUTION_ENABLED=false
ENV IMAGE_MODELS='["gemini-2.0-flash"]'
ENV SEARCH_MODELS='["gemini-2.0-flash"]'


ARG APP_HOME=/app

# 用于添加额外的apt包
ARG APT_PACKAGES=""
# 用于添加额外的pip包
ARG PIP_PACKAGES=""

# 切换到 root 用户以便安装软件包和使用 pip 安装包
USER root

# 使用apt-get代替apk
RUN apt-get update && apt-get install -y git jq curl ${APT_PACKAGES}

# 安装额外的pip包
RUN if [ ! -z "${PIP_PACKAGES}" ]; then pip install ${PIP_PACKAGES}; fi

WORKDIR ${APP_HOME}

COPY ./app /app/app

COPY requirements1.txt .

RUN pip install --no-cache-dir -r requirements1.txt

# 确保文件正确复制到容器中
COPY launch.sh /app/launch.sh
COPY supervisord.conf /app/supervisord.conf
RUN curl -JLO https://github.com/bincooo/SillyTavern-Docker/releases/download/v1.0.0/git-batch

# 确保文件具有正确的执行权限
RUN chmod +x /app/launch.sh && chmod +x /app/git-batch

# 确保目录权限正确
RUN chmod -R 777 ${APP_HOME}

# 可以添加一个验证步骤，确保文件存在
RUN ls -la /app/launch.sh

RUN sed -i 's/\r$//' /app/launch.sh

CMD ["/usr/bin/supervisord", "-c", "/app/supervisord.conf"]
