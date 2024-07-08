# DO NOT MODIFY. This is produced by template.
FROM quay.io/operator-framework/helm-operator@sha256:de2a0a20c1c3b39c3de829196de9694d09f97cd18fda1004de855ed2b4c841ba

# Required OpenShift Labels
LABEL name="Nexus Repository HA Operator" \
      vendor="Sonatype" \
      version="3.68.1" \
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
