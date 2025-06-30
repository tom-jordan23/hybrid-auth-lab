FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install SSH server and essential packages
RUN apt-get update && \
    apt-get install -y \
        openssh-server \
        sudo \
        curl \
        wget \
        vim \
        htop \
        net-tools \
        iputils-ping \
        dnsutils \
        systemd \
        systemd-sysv \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        realmd \
        sssd \
        sssd-tools \
        libnss-sss \
        libpam-sss \
        adcli \
        samba-common-bin \
        oddjob \
        oddjob-mkhomedir \
        packagekit \
        krb5-user \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

# Create vagrant user
RUN useradd -m -s /bin/bash vagrant && \
    echo 'vagrant:vagrant' | chpasswd && \
    usermod -aG sudo vagrant && \
    echo 'vagrant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config

# Generate SSH host keys
RUN ssh-keygen -A

# Create directories for custom configurations
RUN mkdir -p /etc/ssh/custom /home/vagrant/.ssh

# Set up systemd (for SSSD and other services)
RUN systemctl enable ssh && \
    systemctl enable sssd

# Copy startup script
COPY scripts/start-services.sh /usr/local/bin/start-services.sh
RUN chmod +x /usr/local/bin/start-services.sh

# Expose SSH port
EXPOSE 22

# Use systemd as init system
CMD ["/usr/local/bin/start-services.sh"]
