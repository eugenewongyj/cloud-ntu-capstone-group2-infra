FROM alpine:3.22

COPY grafana-plugin/dist/ /opt/capstone/plugins/capstone-sremissioncontrol-panel/
COPY grafana-backend/dist/ /opt/capstone/plugins/capstone-srecontrol-app/

RUN test -s /opt/capstone/plugins/capstone-sremissioncontrol-panel/MANIFEST.txt
RUN test -s /opt/capstone/plugins/capstone-srecontrol-app/MANIFEST.txt
RUN test -x /opt/capstone/plugins/capstone-srecontrol-app/gpx_capstone_srecontrol_linux_amd64
RUN chmod -R a+rX /opt/capstone/plugins

USER 472:472
ENTRYPOINT ["/bin/sh"]
