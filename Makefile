cuda:
	nvcc -arch=sm_32 mm-cuda.cu -o mm-cuda -lcuda -lucudart
