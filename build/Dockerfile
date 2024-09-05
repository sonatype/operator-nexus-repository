# DO NOT MODIFY. This is produced by template.
FROM quay.io/operator-framework/helm-operator@sha256:ecb23393140d2553d97ba9de4d75a7d9aac6a76c9390d22824941e89b983bb68

# Required OpenShift Labels
LABEL name="Nexus Repository HA Operator" \
      vendor="Sonatype" \
      version="3.72.0" \
      release="1" \
      summary="The Nexus Repository with universal support for popular component formats." \
      description="The Nexus Repository with universal support for popular component formats."

USER root

RUN microdnf update -y \
    && microdnf clean all

# back to helm-operator's user
USER 1001

# Required Licenses
COPY licenses /licenses

COPY watches.yaml ${HOME}/watches.yaml
COPY helm-charts/ ${HOME}/helm-charts/
