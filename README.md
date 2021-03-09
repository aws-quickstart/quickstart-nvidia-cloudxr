
---
global:
  marketplace-ami: false
  owner: quickstart-eng@amazon.com
  qsname: quickstart-nvidia-cloudxr
  regions:
    - ap-northeast-1
    - ap-northeast-2
    - ap-southeast-1
    - ap-southeast-2
    - eu-central-1
    - eu-west-1
    - sa-east-1
    - us-east-1
    - us-west-1
    - us-west-2
  reporting: true

tests:
  quickstart-nvidia-cloudxrt1:
    parameter_input: quickstart-nvidia-cloudxr-example-params1.json
    template_file: quickstart-nvidia-cloudxr-example1.template
  quickstart-nvidia-cloudxrt2:
    parameter_input: quickstart-nvidia-cloudxr-example-params2.json
    template_file: quickstart-nvidia-cloudxr-example2.template