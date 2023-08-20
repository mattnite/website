The first thing I’m going to cover here is setting up a bare minimum environment that cross-compiles for a microcontroller (MCU). You can probably do this for Windows, especially since I’ll be using cmake, but I’ll just be using Linux for the development environment. Most of this post is reiterating [Michael Caisse's talk](https://www.youtube.com/watch?v=c9Xt6Me3mJ4) at C++Now 2018, and applying it to a NUCLEO-L073RZ development board by STMicro.

![Look at this bucko](https://media.digikey.com/Photos/STMicro%20Photos/NUCLEO-L073RZ.jpg)

I mostly picked this MCU because it’s made for low power applications which I want to play around with in the future, it’s got a built-in DAC (nice for signal processing), and the GPIO ports can be toggled faster per instruction than other architectures in the STM32 line. It’s also not so big that it’s too complicated to remember all the peripherals, and it comes in SMD packages that are manageable to solder by hand.

## Vendor Tools

STMicro has their own set of tools that make configuration pretty easy called STM32CubeMX, it has a nice UI that lets you select your different clocks, set GPIO modes/alternative functions, and even add in different libraries like capacitive touch and freeRTOS. When you’ve put in what you want, it will generate all your C code and interfaces for your particular project.

There’s also the question of an IDE. There are several options when working with STM32, the open source being called SW4STM32, others include something by IAR, and ARM keil.

Now for my opinions, first: the whole point here is to understand the toolchain, build process, and our hardware, so I don’t care for having all of that work done for me. On top of that, it’s all in C so what’s even the point. What we can do here though is take the output of CubeMx and figure out what it’s actually doing under the hood – especially for the compiler options that we are going to see later. As for the IDE, I don’t actually like them, I’m happy enough using vim and the command line for development, but I like to structure projects so that everyone can use their preferred environment.

## ARM GCC Toolchain

I do love that most MCUs have an ARM core these days since I can use one compiler for mostly everything, and customizing my development is easy. In the past I’ve had to use vendor compilers, and the problem there is that they might force you onto windows, use their IDE, and hide what’s going on under-the-hood, which isn’t a setup for easy performance optimization. The download page for the toolchain is [here](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads). Pick whatever version you want, I just chose the latest since I’ll be working on C++17 and they’ve got all the features stable on [GCC 8](https://www.gnu.org/software/gcc/projects/cxx-status.html).

For installing it on your system, you’ll notice that there are binaries for different OSs and an option to build it from source. I tried from source with no avail, and just copied the extracted folder to /usr/local while adding a new environment variable, ARM_GCC_BIN to point to the binary subdirectory. This variable becomes important to my cmake toolchain file as you’ll see later. I did it this way so that it would be easy to switch versions or so that it could easily be configured on someone else’s machine.

## CMake Toolchain File

Since we’re cross compiling we need to be fairly explicit to cmake as to what compiler we want to use, flags, and other configurations. The best way we can do this is to create a toolchain file which contains all the specifics, and then when running cmake just do the following:

```sh
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain.cmake ..
```

My project is fairly static at this point so I include it in the beginning of my CMakeLists.txt:

```sh
cmake_minimum_required(VERSION 3.0)
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/arm-gcc-toolchain.cmake")
```

All the listings I show you today are going to be fragmented so that I cover the important parts, but you’ll be able to see the full files in my [stm32 repo](https://github.com/matt1795/stm32).  They may change slightly over time, so feel free to email me to ask questions down the line. That being said, it should be fairly clear what goes in what file. So the first thing in our toolchain file we need to do is specify our system and processor:

```cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
```

In our case here, arm is fairly straight forward, but Generic is used for our system name since we’re programming on bare metal, and so there is no OS. Next we set some variables and specify the compilers/binutils:

```cmake
set(TOOLCHAIN_PATH $ENV{ARM_GCC_BIN})
set(CROSS_COMPILE arm-none-eabi-)

set(CMAKE_C_COMPILER    "${TOOLCHAIN_PATH}/${CROSS_COMPILE}gcc")
set(CMAKE_CXX_COMPILER  "${TOOLCHAIN_PATH}/${CROSS_COMPILE}g++")
set(CMAKE_LINKER        "${TOOLCHAIN_PATH}/${CROSS_COMPILE}ld")
set(CMAKE_AR            "${TOOLCHAIN_PATH}/${CROSS_COMPILE}ar")
```

Now one thing cmake does when configuring all of this is validate the compiler by compiling some sort of trivial program. This gets hard to deal with because we need to screw with our cmake cache to get it to work, which I found to make linker configuration difficult in CMakeLists.txt. I know that this compiler is good to go, so I forced cmake to use it without complaint:

```cmake
# force compiler
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
```

This next listing sets the objcopy command so that we can add a step in our build to take the ouput ELF and create a raw binary file that we can flash our board with. We also tell cmake to compile everything statically since dynamic linking isn’t something we get to use on bare metal:

```cmake
set(CMAKE_OBJCOPY "${TOOLCHAIN_PATH}/${CROSS_COMPILE}objcopy"
	CACHE FILEPATH "The toolchain objcopy command" FORCE)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Search for programs in the build host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# For libraries and headers in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

We are going to be setting compiler flags in CMakeLists.txt, but these ones have to do with low-level CPU settings, so they are going to do well here. To be specific we tell the compiler that we are targetting a Cortex-M0+ core, we don’t have a hardware FPU so any floating point operations will be done using software. Our CPU also uses the thumb instruction set which is 16-bit and good for compact code size, finally, the architecture is little endian so we tell the compiler that as well. At the end we store the flags in the cache so that they are used as default values in CMakeLists.txt.

```cmake
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mcpu=cortex-m0plus")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mfloat-abi=soft")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mthumb")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mlittle-endian")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mcpu=cortex-m0plus")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mfloat-abi=soft")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mthumb")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mlittle-endian")

# cache the flags for use
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "CFLAGS")
set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "CXXFLAGS")
set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS}" CACHE STRING "")
```

## STM32CubeL0

The SDK for the L0 family is called STM32CubeL0. It contains a bunch of code we need like the linker script, startup code, examples, libraries, and defs for special-function-registers and the like. I COULD just put it somewhere on my machine and statically point the project to it, but I like making this project “just work” for other users so I have a script to fetch, extract, and cache the sdk (it only does this if it’s not found in the build directory). STMicro actually gets you to jump through some hoops to be able to download the SDK, so I’m actually hosting the zipped file on a private server (please don’t tell on me) for convenience. Later I’d like to look into using conan for package management and see if I can legally host all of STMicro’s SDKs and other libraries for my own use – a post for later.

```sh
#!/bin/bash

SOURCE_DIR=$1
BUILD_DIR=$2
FILE_NAME=en.stm32cubel0.zip
UNPACKED_NAME=STM32Cube_FW_L0_V1.11.0
URL=http://some.url/${FILE_NAME}
STM32_CUBE=stm32-cube

if [ ! -d $STM32_CUBE ]; then
	if [ ! -f $FILE_NAME ]; then
		echo "-- Fetching STM32 CUBE L0"
		wget --no-verbose $URL
	fi

	echo "-- Extracting STM32 CUBE L0"
	unzip -q $FILE_NAME
	mv $UNPACKED_NAME $STM32_CUBE
fi
```

## CMakeLists.txt

This process is relatively simple (that’s why we’ve been working so hard), and I’m going to skim over some of the specifics like the linker script and startup code because they should really get a post of their own. To summarize though:

- set our toolchain file as expected
- call the SKD fetching script
- set our linker script
- set some compiler flags
- include files from SDK that needed to be included (so that it would compile)
- add our ELF executable
- designate that after the ELF is made, make a raw binary file.

Now to talk about some of the important compiler flags:

- `-g`: include debugging symbols
- `-nostartfiles`: dont use standard system startup files (since we're running on bare metal here
- `-Os`: optimizes code for size (REALLY IMPORTANT, I'll do a post on compiler optimization later)
- `-flto`: is for link-time-optimization
- `-DSTM32L073xx`: adds a define (used in SDK code)
- `-MMD`, `-MP`: were in the CubeMx Makefiles, I have no idea what they do at this point

Not included, but will be later on is -fno-rtti, and -fno-exceptions. They are important because RTTI (Run Time Type Information), and exceptions are generally frowned upon for embedded systems due to bloating of the code size. I haven’t included them yet however, because I want to measure what that bloat actually is – I don’t care too much for RTTI, it’s exceptions that I’m curious about.

```cmake
cmake_minimum_required(VERSION 3.0)
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/arm-gcc-toolchain.cmake")
project(stm32 LANGUAGES C CXX ASM)

execute_process(
	COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/fetch_dependencies.sh"
	${CMAKE_CURRENT_SOURCE_DIR}
	WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)

set(STM32_CUBE "${CMAKE_CURRENT_BINARY_DIR}/stm32-cube")
file(GLOB SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")

set(LINKER_SCRIPT
	"${STM32_CUBE}/Projects/NUCLEO-L073RZ/Templates/SW4STM32/STM32L073RZ_NUCLEO/STM32L073RZTx_FLASH.ld")

set(WARNING_FLAGS "${WARNING_FLAGS} -Wall")
set(SHARED_FLAGS "${SHARED_FLAGS} -g -Os -flto -nostartfiles -DSTM32L073xx")
set(SHARED_FLAGS "${SHARED_FLAGS} -MMD -MP")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${SHARED_FLAGS} ${WARNING_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${SHARED_FLAGS} ${WARNING_FLAGS}")

set(CMAKE_EXE_LINKER_FLAGS
	"${CMAKE_EXE_LINKER_FLAGS} -flto -T ${LINKER_SCRIPT}")

include_directories(
	"${STM32_CUBE}/Drivers/CMSIS/Device/ST/STM32L0xx/Include"
	"${STM32_CUBE}/Drivers/CMSIS/Include"
	"${CMAKE_CURRENT_SOURCE_DIR}/include"
)

add_executable(stm32
	"${STM32_CUBE}/Drivers/CMSIS/Device/ST/STM32L0xx/Source/Templates/gcc/startup_stm32l073xx.s"
	${SOURCES}
)

add_custom_command(
	TARGET stm32 POST_BUILD
	COMMAND ${CMAKE_OBJCOPY} stm32 -O binary stm32.bin
	WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
	COMMENT "Convert ELF to binary"
)
```

One hacky thing that I had to do by not using the startfiles is that I needed to resolve the ‘_init’ symbol, so I defined an empty function in one of the files. I really don’t like doing weird archaic stuff like this and I’m not sure if there are any consequences so I want to find a proper solution in the future, but for lighting up an LED, it will do.

```cpp
extern "C" {
void _init(void) {}
}
```

For main, all we’re going to do is turn on LD2. The code does look a little different from what you’re used to in embedded programming for flipping bits, but it’s a register abstraction method that I’ve been playing with and I plan on writing another post on it in the future. Hopefully it’s as readable as I think it is and the bits I’m flipping to get LD2 to light are apparent.

```cpp
int main() {
    Rcc::GpioClkEn::set<0>();

    GpioA::Mode::set<11>();
    GpioA::Bsrr::set<5>();

    while (true) {}
}
```

## Flashing

The Nucleo board I’m using has STLinkV2 on it, so all I need to do is use stlink utilities that are freely and easily available to use. I’m just going to give you this link [here](https://github.com/texane/stlink/blob/master/doc/tutorial.md), the title says it’s for discovery boards, but it works for the Nucleo board no problem.

## Boot Mode

One last detail which is super important for your newly flashed code to work properly, and that is what address the MCU is going to load at boot time. Our little guy can select either flash, system memory, or sram as the boot area and we want flash, and according to the STM32L0 reference manual, that just means grounding the BOOT0 pin.

## Results

After that, you should see your green LD2 light up! It’s a lot of work to just get a damn LED to turn on, but it’s totally worth it. As I’ve mentioned earlier, there are a number of points that I skimmed, all deserving a quick post of their own, and there is so much to look forward to.
