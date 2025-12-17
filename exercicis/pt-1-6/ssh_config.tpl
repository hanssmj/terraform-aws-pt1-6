Host bastion
  HostName ${bastion_ip}
  User ${bastion_user}
  IdentityFile ~/.ssh/${bastion_key}
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ for index, ip in private_ips ~}
Host private-${index + 1}
  HostName ${ip}
  User ${private_user}
  IdentityFile ~/.ssh/${private_keys[index]}
  IdentitiesOnly yes
  ProxyJump bastion
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

%{ endfor ~}
