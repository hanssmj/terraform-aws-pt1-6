output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "private_instances_ips" {
  value = aws_instance.private[*].private_ip
}

output "ssh_config_file" {
  value = "${path.module}/ssh_config_per_connect.txt"
}

output "bucket_name" {
  value = aws_s3_bucket.keys.bucket
}
