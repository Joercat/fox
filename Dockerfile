FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/user
ENV DISPLAY=:0

# Install necessary packages
RUN apt-get update && apt-get install -y \
    tigervnc-standalone-server \
    novnc \
    websockify \
    matchbox-window-manager \
    firefox-esr \
    xterm \
    dbus-x11 \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libpci3 \
    libegl1 \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Create user and required directories
RUN useradd -m user && \
    mkdir -p /home/user/.vnc /home/user/.mozilla /home/user/.cache && \
    chown -R user:user /home/user && \
    mkdir -p /var/log/supervisor

# 1. Create the start-vnc script
RUN cat <<EOF > /start-vnc.sh
#!/bin/bash
# Clean up existing locks
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null
# Start VNC server (fixed flags for TigerVNC 1.12+)
exec Xvnc :0 \\
    -geometry 1280x720 \\
    -depth 24 \\
    -rfbport 5900 \\
    -SecurityTypes None \\
    -AlwaysShared \\
    -AcceptKeyEvents \\
    -AcceptPointerEvents \\
    -SendCutText \\
    -AcceptCutText
EOF

# 2. Create the start-firefox script
RUN cat <<EOF > /start-firefox.sh
#!/bin/bash
# Wait for VNC and Window Manager to be ready
sleep 5
# Ensure D-Bus is running for Firefox
if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval \$(dbus-launch --sh-syntax)
fi
exec firefox-esr \\
    --no-remote \\
    --new-instance \\
    --setDefaultBrowser \\
    --disable-crash-reporter
EOF

# 3. Create the supervisord config
RUN cat <<EOF > /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/var/log/supervisor

[program:vnc]
command=bash /start-vnc.sh
autostart=true
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:matchbox]
command=/usr/bin/matchbox-window-manager -use_titlebar no -use_cursor yes
environment=DISPLAY=":0",HOME="/home/user"
user=user
autostart=true
autorestart=true
priority=20
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:firefox]
command=bash /start-firefox.sh
user=user
environment=DISPLAY=":0",HOME="/home/user"
autostart=true
autorestart=true
priority=30
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:websockify]
command=/usr/bin/websockify --web=/usr/share/novnc/ 7860 localhost:5900
autostart=true
autorestart=true
priority=40
startsecs=2
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Make scripts executable
RUN chmod +x /start-vnc.sh /start-firefox.sh

EXPOSE 7860

# Start Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
