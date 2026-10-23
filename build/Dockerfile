# DO NOT MODIFY. This is produced by template.
FROM quay.io/operator-framework/helm-operator@sha256:ecb23393140d2553d97ba9de4d75a7d9aac6a76c9390d22824941e89b983bb68

# Required OpenShift Labels
LABEL name="Nexus Repository HA Operator" \
      vendor="Sonatype" \
      version="3.97.2" \
      release="1" \
      summary="The Nexus Repository with universal support for popular component formats." \
      description="The Nexus Repository with universal support for popular component formats." \
      maintainer="Sonatype for Red Hat OpenShift"

USER root

RUN microdnf update -y \
    && microdnf clean all

# Distrust the roots of the compromised eMudhra intermediate CAs (NEXUS-56000).
# Remove once the base image ships a ca-certificates without them.
RUN d=/etc/pki/ca-trust/source/blocklist; [ -d "$d" ] || d=/etc/pki/ca-trust/source/blacklist; \
    trust extract --overwrite --format=pem-bundle \
      --filter='pkcs11:object=Comodo%20AAA%20Services%20root;type=cert' "$d/Comodo_AAA_Services_root.pem" \
    && trust extract --overwrite --format=pem-bundle \
      --filter='pkcs11:object=emSign%20ECC%20Root%20CA%20-%20G3;type=cert' "$d/emSign_ECC_Root_CA_-_G3.pem" \
    && update-ca-trust

# back to helm-operator's user
USER 1001

# Required Licenses
COPY licenses /licenses

COPY watches.yaml ${HOME}/watches.yaml
COPY helm-charts/ ${HOME}/helm-charts/
