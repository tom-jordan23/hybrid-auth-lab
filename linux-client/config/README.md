# Configuration Files

This directory contains configuration files that can be imported into the running containers.

## File Organization

- `exported/` - Auto-exported configurations from running containers
- `*.sample` - Template files that you can copy and modify
- Individual config files for direct use

## Sample Configurations

- `sssd.conf.sample` - SSSD configuration for Active Directory integration
- `krb5.conf.sample` - Kerberos configuration
- `sshd_config.sample` - SSH daemon configuration with AD support

## Usage

1. Copy sample files and modify for your environment:
   ```bash
   cp sssd.conf.sample sssd.conf
   # Edit sssd.conf with your domain settings
   ```

2. Import configurations to running container:
   ```bash
   ./config-manager.sh import sshd
   ```

3. Export current configurations from container:
   ```bash
   ./config-manager.sh export sshd
   ```

## Active Directory Integration

To join the Ubuntu client to your Windows AD domain:

1. Configure `sssd.conf` with your domain settings
2. Configure `krb5.conf` with your realm settings  
3. Import the configurations: `./config-manager.sh import sshd`
4. Join the domain from within the container:
   ```bash
   ssh vagrant@localhost -p 2222
   sudo realm join example.com
   ```
