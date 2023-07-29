# Account ID
variable account_id {
    type        = string
}

# Project Name
variable project {
    type        = string
}

# Environment (dev / stg / prod)
variable environment {
    type        = string
}

# Region
variable region {
    type        = string
}

# Number of Availability Zone to use
variable num_azs {
    type              = number
    validation {
        condition     = var.num_azs >= 1 && var.num_azs <= 3
        error_message = "The value must be between 1 and 3"
    }
}

# Docker container image name
variable image_name {
    type        = string
}

# Docker container image tag
variable image_tag {
    type        = string
}
