output "sshuttle" {
  value = [for k, v in var.instances :
    "sshuttle -x ${module.instances[k].public_ip} --dns -NHr opc@${module.instances[k].public_ip} ${module.vcns[var.subnets[v.create_vnic_details.subnet_name].vcn_name].cidr_blocks[0]}"
  ]
}

output "vcns" {
  value = { for k, v in module.vcns :
    k => {
      display_name = v.display_name
      id           = v.id
      cidr_blocks  = v.cidr_blocks
      subnets = [for i, j in module.subnets :
        {
          name       = i
          cidr_block = j.cidr_block
        } if j.vcn_id == v.id
      ]
    }
  }
}

output "instances" {
  value = { for k, v in module.instances :
    k => {
      id         = v.id
      public_ip  = v.public_ip == "" ? null : v.public_ip
      private_ip = v.private_ip
    }
  }
}
