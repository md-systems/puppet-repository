# == Class: repository
#
# Installs and configures a Debian repository.
#
# NOTE: This module needs manual steps for installation to work.
#
# == Manual installation steps
#
# Before first provisioning, create a gpg key.
#
#  gpg --gen-key
#  gpg --export --armor info@example.com > /etc/puppet/modules/repository/files/localpkgs.gpg
#
# Use the key id when setting up the repository. See example below.
#
# Once the repository was installed the gpg private key needs to be imported to
# the keychain of the user reprepro.
#
#  gpg --export-secret-key -a info@example.com > /var/packages/localpkgs.key
#  sudo -s -u reprepro
#  gpg --allow-secret-key-import --import /var/packages/localpkgs.key
#
# === Adding a package
#
# In order to add a package to the repository, copy it to
# ${basedir}/localpkgs/tmp/stable. The package will be picked up on cron run and
# imported to the repository.
#
# === Variables
#
# [*key_id*]
#   ID of the gpg key used
#
# [*key_file*]
#   Path to file containing the public gpg key,
#
# [*domain*]
#   The domain the repository should be accessible.
#   Defaults to 'apt.md-systems.ch.ch'.
#
# [*ip*]
#   The ip used by the apache vhost created for the repository.
#   Defaults to the systems default ip address.
#
# [*basedir*]
#   Base Directory for the repository. Defaults to '/var/lib/apt/repo'.
#
# === Examples
#
#  class { 'repository':
#    $key_id = 'C3858C15',
#    $key_file = 'puppet:///modules/repository/localpkgs.gpg',
#    $basedir = '/var/lib/apt/repo',
#  }
#
# === Authors
#
# Christian Haeusler <christian.haeusler@md-systems.ch>
#
# === Copyright
#
# Copyright 2013 MD Systems.
#
class repository (
  $key_id,
  $key_file,
  $release = 'wheezy',
  $domain = 'apt.md-systems.ch',
  $ip = $::ipaddress,
  $basedir = '/var/lib/apt/repo'
) {

  class { 'reprepro':
    basedir => $basedir,
  }

  # Set up a repository
  reprepro::repository { 'localpkgs':
    ensure  => present,
    basedir => $basedir,
    options => ['basedir .'],
  }

  # Create a distribution within that repository
  reprepro::distribution { $release:
    basedir       => $basedir,
    repository    => 'localpkgs',
    origin        => 'MD Systems',
    label         => 'MD Systems Repository',
    suite         => 'stable',
    architectures => 'amd64 i386',
    components    => 'main contrib non-free',
    description   => 'Repository for packages used by MD Systems',
    sign_with     => $key_id,
    not_automatic => 'No',
  }

  # Set up apache
  class { 'apache': }

  # Make your repo publicly accessible
  apache::vhost { 'localpkgs':
    port              => '80',
    docroot           => '/var/lib/apt/repo/localpkgs',
    servername        => $domain,
    access_log_pipe   => '||/opt/lumberjack/bin/lumberjack.sh -log-to-syslog=true -config=/etc/lumberjack/lumberjack.conf -',
    access_log_format => '{ \"@timestamp\": \"%{%Y-%m-%dT%H:%M:%S%z}t\", \"@message\": \"%r\", \"@fields\": { \"user-agent\": \"%{User-agent}i\", \"client\": \"%a\", \"duration_usec\": %D, \"duration_sec\": %T, \"status\": %s, \"request_path\": \"%U\", \"request\": \"%U%q\", \"method\": \"%m\", \"referrer\": \"%{Referer}i\" } }',
    require           => Reprepro::Distribution[$release],
  }

  # Ensure your public key is accessible to download
  file { '/var/lib/apt/repo/localpkgs/localpkgs.gpg':
    ensure  => present,
    owner   => 'www-data',
    group   => 'reprepro',
    mode    => '0644',
    source  => $key_file,
    require => Apache::Vhost['localpkgs'],
  }

  # Set up an apt repo and make it available for all managed systems.
  @@apt::source { 'localpkgs':
    location    => "http://${domain}",
    release     => $release,
    repos       => 'main contrib non-free',
    key         => $key_id,
    key_source  => "http://${domain}/localpkgs.gpg",
    include_src => false,
    tag         => [$::company, $::location, "${::company}-${::location}"]
  }

  # Add a dns record for this repository.
  @@dnsmasq::address {$domain:
    ip  => $ip,
    tag => $::location,
  }
}
