
sudo chmod -R 555 /var/log/

# get path of this script,
# ref http://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
pushd `dirname $0` > /dev/null
gThisScriptPath=`pwd`
gThisScriptName=`basename "$0"`
gScriptFullName=${gScript_Path}/${gScript_Name}
popd > /dev/null

gScriptPath="$gThisScriptPath/scripts"
gInsertToFileScript="$gScriptPath/insertToFile.sh"
gInsertFunctionToBash="$gScriptPath/insertFunctionToBash.sh"
source ${gInsertToFileScript}
source ${gInsertFunctionToBash}
source ${gScriptPath}/install_ubuntu.bash

# clang debain
# newest
# sudo add-apt-repository "deb http://apt.llvm.org/trusty/ llvm-toolchain-trusty main"
# sudo add-apt-repository "deb-src http://apt.llvm.org/trusty/ llvm-toolchain-trusty main"
# clang 3.8


wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key|sudo apt-key add -

sudo apt-get update

sudo apt-get install -y build-essential
sudo apt-get install -y git
sudo apt-get install -y gitk
sudo apt-get install -y vim
sudo apt-get install -y meld
sudo apt-get install -y terminator
sudo apt-get install -y htop
sudo apt-get install -y python-wstool
sudo apt-get install -y xclip
sudo apt-get install -y openssh-server
sudo apt-get install -y sshpass
sudo apt-get install -y python-setuptools
sudo apt-get install -y python-pip
sudo apt-get install --force-yes python3-pip
sudo pip3 install Plumbum
sudo pip3 install backtrace

# install openrave-ikfast
# reference http://docs.ros.org/jade/api/moveit_ikfast/html/doc/ikfast_tutorial.html
sudo apt-get install -y openrave0.8-dp-ikfast
insertAfterLine "/usr/lib/python2.7/dist-packages/openravepy/__init__.py" \



sudo easy_install pip

# install ros


# nlopt, needed by trac ik
sudo apt-get install -y libnlopt-dev

sudo apt-get install -y cmake  libgtest-dev 
sudo apt-get install -y ros-indigo-catkin

source /opt/ros/indigo/setup.bash

sudo rosdep init
rosdep update
mkdir -p ~/workspace/src
cd ~/workspace/src
sudo chmod -R 777 ~/workspace/src/*
catkin_init_workspace
cd ../
catkin_make
source devel/setup.bash

exportPath()
{
	eval $@
	echo $@ >> ~/.bashrc
}

exportPath 'export RD_ROS_WORKSPACE=~/workspace'
exportPath 'export RD_LIB_PATH=~/library/'
mkdir -p $RD_LIB_PATH

exportPath 'export RD_SYSTEM_CONFIG_DIR=/var/rd-config'
sudo mkdir -p $RD_SYSTEM_CONFIG_DIR
sudo chmod 777 -R $RD_SYSTEM_CONFIG_DIR

exportPath 'export RD_LOG_DIR=/var/rd-logs'
sudo mkdir -p $RD_LOG_DIR
sudo chmod 777 -R $RD_LOG_DIR


echo '########## system_setup.bash  START' >> ~/.bashrc

echo source ${ROS_ROOT_PATH}/setup.bash >> ~/.bashrc
echo source ${RD_ROS_WORKSPACE}/devel/setup.bash >> ~/.bashrc

echo alias ymake="'catkin_make install -DCMAKE_INSTALL_PREFIX:PATH=$ROS_WORKSPACE_INSTALL_PATH -C ${RD_ROS_WORKSPACE} -DCMAKE_BUILD_TYPE=Debug'" >> ~/.bashrc
echo alias ymakerelease="'catkin_make install -DCMAKE_INSTALL_PREFIX:PATH=$ROS_WORKSPACE_INSTALL_PATH -C ${RD_ROS_WORKSPACE} -DCMAKE_BUILD_TYPE=Release'" >> ~/.bashrc
echo alias ytest="'(yhome && cd ../build/ && ctest)'" >> ~/.bashrc

echo alias rhome="'cd ${RD_LIB_PATH}/RD_FreeCAD'" >> ~/.bashrc
echo alias rmake="'(rhome && cd build && cmake .. -DCMAKE_INSTALL_PREFIX:PATH=./install/ -DCMAKE_BUILD_TYPE=Debug && make -j6)'" >> ~/.bashrc
# fast rmake do not reconfig cmake, will not work if add new files or any changes to cmake
echo alias frmake="'(rhome && cd build && make -j6 -f CMakeFiles/Makefile2)'" >> ~/.bashrc
echo alias rmakerelease="'(rhome && cd build && cmake .. -DCMAKE_INSTALL_PREFIX:PATH=./install/ -DCMAKE_BUILD_TYPE=Release && make -j6)'" >> ~/.bashrc
echo alias clion-keyboard-fix="'killall -9 ibus-x11'" >> ~/.bashrc
echo alias gitpruneRemote="'git fetch origin --prune'" >> ~/.bashrc
# this is to auto start/stop robot launch file
echo alias startRobotRoslaunch="'${RD_SETUP_SCRIPT_PATH}/dev/start-auto-roslaunch.sh start'" >> ~/.bashrc
echo alias stopRobotRoslaunch="'${RD_SETUP_SCRIPT_PATH}/dev/start-auto-roslaunch.sh stop'" >> ~/.bashrc
ROS_EXPORT_VAR='export ROSCONSOLE_FORMAT='"'"'[${severity}] [${time} ${file} ${line}]: ${message}'"'"
echo "$ROS_EXPORT_VAR" >> ~/.bashrc

python3 setup_indigo_14.04.py
echo '########## system_setup.bash  END' >> ~/.bashrc
source ~/.bashrc

cd ${RD_LIB_PATH}
sh ${RD_SETUP_SCRIPT_PATH}/install_gcc6.sh
sh ${RD_SETUP_SCRIPT_PATH}/install-vendor-library.sh
sh ${RD_SETUP_SCRIPT_PATH}/dev/download-repo.sh
# python path problem was solved in FreeCAD
# sh ${RD_SETUP_SCRIPT_PATH}/scripts/insertToFile.sh

