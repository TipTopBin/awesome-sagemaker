#!/bin/bash

set -e

# https://github.com/aws-samples/amazon-sagemaker-notebook-instance-lifecycle-config-samples/blob/master/scripts/persistent-conda-ebs/on-start.sh
# https://medium.com/@nrk25693/how-to-add-your-conda-environment-to-your-jupyter-notebook-in-just-4-steps-abeab8b8d084
# OVERVIEW
# This script installs a custom, persistent installation of conda on the Notebook Instance's EBS volume, and ensures
# that these custom environments are available as kernels in Jupyter.
#
# The on-start script uses the custom conda environment created in the on-create script and uses the ipykernel package
# to add that as a kernel in Jupyter.
#
# For another example, see:
# https://docs.aws.amazon.com/sagemaker/latest/dg/nbi-add-external.html#nbi-isolated-environment

sudo -u ec2-user -i <<'EOF'
unset SUDO_UID
WORKING_DIR=/home/ec2-user/SageMaker/custom/tf29-p38
source "$WORKING_DIR/miniconda/bin/activate"
for env in $WORKING_DIR/miniconda/envs/*; do
    BASENAME=$(basename "$env")
    source activate "$BASENAME"
    python -m ipykernel install --user --name "$BASENAME" --display-name "Custom ($BASENAME)"
done
# Optionally, uncomment these lines to disable SageMaker-provided Conda functionality.
# echo "c.EnvironmentKernelSpecManager.use_conda_directly = False" >> /home/ec2-user/.jupyter/jupyter_notebook_config.py
# rm /home/ec2-user/.condarc
EOF

echo "Config SSH ..."
export LOCAL_PUBLIC_KEY="xxxxx"
cat >> /home/ec2-user/.ssh/authorized_keys <<EOF
${LOCAL_PUBLIC_KEY}
EOF

echo "Restarting the Jupyter server ..."
sudo systemctl restart jupyter-server