
sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
sudo apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key 0xB01FA116

sudo apt-get update

sudo apt-get install -y build-essential
sudo apt-get install -y git
sudo apt-get install -y gitk
sudo apt-get install -y vim
sudo apt-get install -y meld
sudo apt-get install -y terminator
sudo apt-get install -y htop
sudo apt-get install -y python-wstool


# install ros
sudo apt-get install -y ros-jade-desktop-full
#install moveit
#sudo apt-get install -y ros-jade-moveit-full


sudo apt-get install -y cmake python-catkin-pkg python-empy python-nose python-setuptools libgtest-dev build-essential
sudo apt-get install -y ros-jade-catkin

source /opt/ros/jade/setup.bash

sudo rosdep init
rosdep update
mkdir -p ~/workspace/src
cd ~/workspace/src
sudo chmod -R 777 ~/workspace/src/
catkin_init_workspace
cd ../
catkin_make
source devel/setup.bash

echo '########## system_setup.bash  START' >> ~/.bashrc
echo source /opt/ros/jade/setup.bash >> ~/.bashrc
echo source ~/workspace/devel/setup.bash >> ~/.bashrc
echo alias yhome="'cd ~/workspace/src/'" >> ~/.bashrc
echo alias ymake="'catkin_make install -DCMAKE_INSTALL_PREFIX:PATH=~/workspace/install -C ~/workspace -DCMAKE_BUILD_TYPE=Debug'" >> ~/.bashrc
echo alias ymakerelease="'catkin_make install -DCMAKE_INSTALL_PREFIX:PATH=~/workspace/install -C ~/workspace -DCMAKE_BUILD_TYPE=Release'" >> ~/.bashrc
echo export ROS_PACKAGE_PATH=~/workspace/src/:/opt/ros/jade/share:$ROS_PACKAGE_PATH >> ~/.bashrc

echo '########## system_setup.bash  END' >> ~/.bashrc
source ~/.bashrc

