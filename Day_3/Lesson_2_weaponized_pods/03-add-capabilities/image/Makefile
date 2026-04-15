obj-m += Totally_Legit_Module.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
