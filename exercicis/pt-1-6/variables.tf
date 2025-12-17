variable "region" {
  type    = string
  default = "us-east-1"
}

variable "private_instance_count" {
  type    = number
  default = 2

  validation {
    condition     = var.private_instance_count >= 1 && var.private_instance_count <= 10
    error_message = "private_instance_count debe estar entre 1 y 10."
  }
}

variable "allowed_ip" {
  type = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.allowed_ip))
    error_message = "allowed_ip debe tener formato x.x.x.x/32."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_user" {
  type    = string
  default = "ec2-user"
}
