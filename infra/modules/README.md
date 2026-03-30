# Example reusable module structure for platform resources

This directory contains reusable terraform modules for your platform.

## Module Template

Create a subdirectory for each module:

```
infra/modules/example-module/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

## Usage in Stack

```hcl
module "example" {
  source = "../modules/example-module"
  
  # pass variables as needed
}
```

## Best Practices

- Each module should be independently testable
- Use descriptive variable names
- Provide sensible defaults where applicable
- Document all outputs
- Keep modules focused on a single concern
