# Packages trainer/ for Vertex AI's prebuilt scikit-learn training container.
# live-setup.sh builds the source distribution itself, so no local Docker is needed.
from setuptools import find_packages, setup

setup(name="qc_fuel_trainer", version="0.1", packages=find_packages(include=["trainer"]))
