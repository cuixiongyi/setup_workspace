python3 - <<'PY' > ros.env
import os

keys = [
    "PATH",
    "PYTHONPATH",
    "LD_LIBRARY_PATH",
    "AMENT_PREFIX_PATH",
    "COLCON_PREFIX_PATH",
    "ROS_DISTRO",
    "ROS_VERSION",
    "ROS_PYTHON_VERSION",
    "ROS_DOMAIN_ID",
    "RMW_IMPLEMENTATION",
]

for k in keys:
    v = os.environ.get(k)
    if v:
        print(f"{k}={v}")
PY
