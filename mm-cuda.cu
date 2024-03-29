/**
 * 
 * Matrix Multiplication - CUDA for GPUs
 *
 * CS3210
 *
 **/
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <assert.h>

int size;

const int BLOCK_SIZE = 16;

typedef struct
{
	float ** element;
} matrix;


long long wall_clock_time()
{
#ifdef __linux__
	struct timespec tp;
	clock_gettime(CLOCK_REALTIME, &tp);
	return (long long)(tp.tv_nsec + (long long)tp.tv_sec * 1000000000ll);
#else
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return (long long)(tv.tv_usec * 1000 + (long long)tv.tv_sec * 1000000000ll);
#endif
}

/**
 * Allocates memory for a matrix of size SIZE
 * The memory is allocated row-major order, i.e. 
 *  elements from the same row are allocated at contiguous 
 *  memory addresses.
 **/
void allocate_matrix(matrix* m)
{
	int i;
	cudaError_t rc;
	
	// allocate array for all the rows
	rc = cudaMallocManaged((void**)&(m->element), sizeof(float*) * size);
	if (rc != cudaSuccess)
	{
		fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(rc));
		exit(1);
	}
	
	// allocate an array for each row of the matrix
	for (i = 0; i < size; i++)
	{
		rc = cudaMallocManaged((void**)&(m->element[i]), sizeof(float) * size);
		if (rc != cudaSuccess)
		{
			fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(rc));
			exit(1);
		}
	}
}

/**
 * Free the memory allocated for a matrix.
 **/
void free_matrix(matrix* m) {
	int i;
	for (i = 0; i < size; i++)
		cudaFree(m->element[i]);
	cudaFree(m->element);
}

/**
 * Initializes the elements of the matrix with
 * random values between 0 and 9
 **/
void init_matrix(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
		{
			m.element[i][j] = rand() % 10;
		}
}

/**
 * Initializes the elements of the matrix with
 * element 0.
 **/
void init_matrix_zero(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
		{
			m.element[i][j] = 0.0;
		}
}


/**
 * Multiplies matrix @a with matrix @b storing
 * the result in matrix @result
 * 
 * The multiplication algorithm is the O(n^3) 
 * algorithm
 */
void mm(matrix a, matrix b, matrix result)
{
	int i, j, k;
	
	// Do the multiplication
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
			for(k = 0; k < size; k++)
				result.element[i][j] += a.element[i][k] * b.element[k][j];
}

/**
 * Each kernel computes the result element (i,j).
 */
__global__ void mm_kernel(matrix a, matrix b, matrix result, int size)
{
        // Block index
        int bx = blockIdx.x;
        int by = blockIdx.y;

        // Thread index
        int tx = threadIdx.x;
        int ty = threadIdx.y;

        // begin of the first sub-matrix of a processed by the block
        int aBegin = size * BLOCK_SIZE * by;
        int aEnd = aBegin + size - 1;
        int aStep = BLOCK_SIZE;

        int bBegin = BLOCK_SIZE * bx;
        int bStep = BLOCK_SIZE * size;
        
        float Csub = 0;

        for (int _a = aBegin, _b = bBegin;
             _a <= aEnd;
             _a += aStep, _b += bStep) {
            
            __shared__ float As[BLOCK_SIZE][BLOCK_SIZE];
            __shared__ float Bs[BLOCK_SIZE][BLOCK_SIZE];
            int a_index = _a + size * ty + tx;
            int a_i = a_index / size;
            int a_j = a_index % size;

            int b_index = _b + size * ty + tx;
            int b_i = b_index / size;
            int b_j = b_index % size;

            As[ty][tx] = a_i < size ? a.element[a_i][a_j] : 0;
            Bs[ty][tx] = b_i < size ? b.element[b_i][b_j] : 0;

            __syncthreads();

            for (int k = 0; k < BLOCK_SIZE; k++) {
                Csub += As[ty][k] * Bs[k][tx];
            }

            __syncthreads();

        }

        int c_index = size * BLOCK_SIZE * by + BLOCK_SIZE * bx + size * ty + tx;
        int c_i = c_index / size;
        int c_j = c_index % size;
        result.element[c_i][c_j] = Csub;
}

void print_matrix(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
	{
		printf("row %4d: ", i);
		for (j = 0; j < size; j++)
			printf("%6.2f  ", m.element[i][j]);
		printf("\n");
	}
}



void work()
{
	matrix a, b, result1, result2;

	long long before, after;
	int correct, i, j, dim;
	cudaError_t rc;

	// Allocate memory for matrices
	allocate_matrix(&a);
	allocate_matrix(&b);
	allocate_matrix(&result1);
	allocate_matrix(&result2);

	// Initialize matrix elements
	init_matrix(a);
	init_matrix(b);

	before = wall_clock_time();
	mm(a, b, result1);
	after = wall_clock_time();
        fprintf(stderr, "Matrix multiplication on CPU took %1.2f seconds\n", ((float)(after - before))/1000000000);

	// Perform CUDA matrix  multiplication
	dim3 block(BLOCK_SIZE, BLOCK_SIZE);			// a block of 32 x 32 CUDA threads
	dim = (size % BLOCK_SIZE == 0) ? size / BLOCK_SIZE : size / BLOCK_SIZE + 1; 
	dim3 grid(dim, dim);	// a grid of CUDA thread blocks

	before = wall_clock_time();
	mm_kernel<<<grid, block>>>(a, b, result2, size);
	cudaDeviceSynchronize();
	after = wall_clock_time();

	fprintf(stderr, "Matrix multiplication on GPU took %1.2f seconds\n", ((float)(after - before))/1000000000);

	// was there any error?
        rc = cudaGetLastError();
        if (rc != cudaSuccess)
                printf("Last CUDA error %s\n", cudaGetErrorString(rc));

	// Compare the results
	correct = 1;
	for (i = 0; correct && i < size; i++)
		for (j = 0; j < size; j++)
			if (result1.element[i][j] != result2.element[i][j]) {
				correct = 0;
				break;
			}

	if (correct)
		printf("The result matrices are identical!\n");
	else
		printf("Difference in result matrices at element (%d, %d)!\n", i, j);

	free_matrix(&a);
	free_matrix(&b);
	free_matrix(&result1);
	free_matrix(&result2);
}


int main(int argc, char ** argv)
{
	srand(0); 

	printf("Usage: %s <size>\n", argv[0]);
    
	if (argc >= 2)
		size = atoi(argv[1]);
	else
		size = 1024;
		
	fprintf(stderr,"Sequential matrix multiplication of size %d\n", size);
    
	// Multiply the matrices
	work();

	return 0;
}
