# DO NOT MODIFY. This is produced by template.
FROM quay.io/operator-framework/helm-operator@sha256:e82703bd9ce640b048c00d0c2e860d784cd0c5bfb724869c1aba85e92a13ce58

# Required OpenShift Labels
LABEL name="Nexus Repository HA Operator" \
      vendor="Sonatype" \
      version="3.60.0" \
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
