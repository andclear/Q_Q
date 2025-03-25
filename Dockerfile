FROM ghcr.io/moyangking/astrbot-lagrange-docker:main

EXPOSE 6185

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

ADD launch.sh launch.sh
ADD supervisord.conf supervisord.conf
RUN curl -JLO  https://github.com/bincooo/SillyTavern-Docker/releases/download/v1.0.0/git-batch
RUN chmod +x launch.sh && chmod +x git-batch

RUN chmod -R 777 ${APP_HOME}
# 修改成先执行环境设置，再执行初始化
CMD ["/usr/bin/supervisord", "-c", "/app/supervisord.conf"]