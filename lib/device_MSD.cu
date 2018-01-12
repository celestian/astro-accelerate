#include <helper_cuda.h>

#include "headers/device_single_FIR.h"
#include "headers/device_bin.h"
#include "headers/device_MSD_Configuration.h"

#include "device_MSD_shared_kernel_functions.cu"
#include "device_MSD_normal_kernel.cu"
#include "device_MSD_outlier_rejection_kernel.cu"

#include <vector>

//#define MSD_DEBUG
//#define MSD_PLANE_DEBUG
//#define MSD_PLANE_EXPORT

// TODO:
// Remove MSD_legacy

void MSD_init(void) {
	//---------> Specific nVidia stuff
	cudaDeviceSetCacheConfig (cudaFuncCachePreferShared);
	cudaDeviceSetSharedMemConfig (cudaSharedMemBankSizeFourByte);
}



//---------------------------------------------------------------
//------------- MSD without outlier rejection

int MSD_normal(float *d_MSD, float *d_input, float *d_temp, MSD_Configuration *MSD_conf) {
	
	#ifdef MSD_DEBUG
	MSD_conf->print();
	#endif

	MSD_init();
	MSD_GPU_limited<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset);
	MSD_GPU_final_regular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
	
	#ifdef MSD_DEBUG
	float h_MSD[MSD_PARTIAL_SIZE];
	checkCudaErrors(cudaMemcpy(h_MSD, d_MSD, MSD_PARTIAL_SIZE*sizeof(float), cudaMemcpyDeviceToHost)); 
	printf("Output: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif

	return (0);
}

int MSD_normal(float *d_MSD, float *d_input, int nTimesamples, int nDMs, int offset){
	int result;
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	float *d_temp;
	checkCudaErrors(cudaMalloc((void **) &d_temp, conf.nBlocks_total*MSD_PARTIAL_SIZE*sizeof(float)));
	result = MSD_normal(d_MSD, d_input, d_temp, &conf);
	checkCudaErrors(cudaFree(d_temp));
	return(result);
}



int MSD_normal_continuous(float *d_MSD, float *d_input, float *d_previous_partials, float *d_temp, MSD_Configuration *MSD_conf) {

	#ifdef MSD_DEBUG
	MSD_conf->print();
	#endif

	MSD_init();
	MSD_GPU_limited<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset);
	MSD_GPU_final_regular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, d_previous_partials, MSD_conf->nBlocks_total);
	
	#ifdef MSD_DEBUG
	float h_MSD[3];
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Output: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif

	return (0);
}

int MSD_normal_continuous(float *d_MSD, float *d_input, float *d_previous_partials, int nTimesamples, int nDMs, int offset){
	int result;
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	float *d_temp;
	cudaMalloc((void **) &d_temp, conf.nBlocks_total*MSD_PARTIAL_SIZE*sizeof(float));
	result = MSD_normal_continuous(d_MSD, d_input, d_previous_partials, d_temp, &conf);
	cudaFree(d_temp);
	return(result);
}

//------------- MSD without outlier rejection
//---------------------------------------------------------------


//---------------------------------------------------------------
//------------- MSD with outlier rejection

//MSD_BLN_pw
int MSD_outlier_rejection(float *d_MSD, float *d_input, float *d_temp, MSD_Configuration *MSD_conf, float OR_sigma_multiplier){
	#ifdef MSD_DEBUG
	float h_MSD[3];
	MSD_conf->print();
	#endif
	
	MSD_init();
	MSD_GPU_limited<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset);
	MSD_GPU_final_regular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Before outlier rejection: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	for(int i=0; i<5; i++){
		MSD_BLN_pw_rejection_normal<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD,  MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset, OR_sigma_multiplier);
		MSD_GPU_final_nonregular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
		#ifdef MSD_DEBUG
		cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
		printf("Rejection %d: Mean: %e, Standard deviation: %e; Elements:%zu;\n", i, h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
		printf("---------------------------<\n");
		#endif
	}
	
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Output: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	
	return(0);
}


int MSD_outlier_rejection(float *d_MSD, float *d_input, int nTimesamples, int nDMs, int offset, float OR_sigma_multiplier) {
	int result;
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	float *d_temp;
	cudaMalloc((void **) &d_temp, conf.nBlocks_total*MSD_PARTIAL_SIZE*sizeof(float));
	result = MSD_outlier_rejection(d_MSD, d_input, d_temp, &conf, OR_sigma_multiplier);
	cudaFree(d_temp);
	return(result);
}


//MSD_BLN_pw_continuous
int MSD_outlier_rejection_continuous(float *d_MSD, float *d_input, float *d_previous_partials, float *d_temp, MSD_Configuration *MSD_conf, float OR_sigma_multiplier){
	#ifdef MSD_DEBUG
	float h_MSD[3];
	MSD_conf->print();
	#endif
	
	MSD_init();
	MSD_GPU_limited<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset);
	MSD_GPU_final_regular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Before outlier rejection: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	for(int i=0; i<5; i++){
		MSD_BLN_pw_rejection_normal<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD,  MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset, OR_sigma_multiplier);
		MSD_GPU_final_nonregular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
		#ifdef MSD_DEBUG
		cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
		printf("Rejection %d: Mean: %e, Standard deviation: %e; Elements:%zu;\n", i, h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
		printf("---------------------------<\n");
		#endif
	}
	MSD_GPU_final_nonregular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, d_previous_partials, MSD_conf->nBlocks_total);
	
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Output: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	
	return(0);
}


int MSD_outlier_rejection_continuous(float *d_MSD, float *d_input, float *d_previous_partials, int nTimesamples, int nDMs, int offset, float OR_sigma_multiplier) {
	int result;
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	float *d_temp;
	cudaMalloc((void **) &d_temp, conf.nBlocks_total*MSD_PARTIAL_SIZE*sizeof(float));
	result = MSD_outlier_rejection_continuous(d_MSD, d_input, d_previous_partials, d_temp, &conf, OR_sigma_multiplier);
	cudaFree(d_temp);
	return(result);
}


//MSD_BLN_pw_continuous_OR
int MSD_outlier_rejection_grid(float *d_MSD, float *d_input, float *d_previous_partials, float *d_temp, MSD_Configuration *MSD_conf, float OR_sigma_multiplier){	
	#ifdef MSD_DEBUG
	float h_MSD[3];
	MSD_conf->print();
	#endif
	
	MSD_init();
	MSD_GPU_limited<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset);
	MSD_GPU_final_regular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Before outlier rejection: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	for(int i=0; i<5; i++){
		MSD_BLN_pw_rejection_normal<<<MSD_conf->partials_gridSize,MSD_conf->partials_blockSize>>>(d_input, &d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD,  MSD_conf->nSteps.y, (int) MSD_conf->nTimesamples, (int) MSD_conf->offset, OR_sigma_multiplier);
		MSD_GPU_final_nonregular<<<MSD_conf->final_gridSize,MSD_conf->final_blockSize>>>(&d_temp[MSD_conf->address*MSD_PARTIAL_SIZE], d_MSD, MSD_conf->nBlocks_total);
		#ifdef MSD_DEBUG
		cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
		printf("Rejection %d: Mean: %e, Standard deviation: %e; Elements:%zu;\n", i, h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
		printf("---------------------------<\n");
		#endif
	}
	
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Before grid rejection: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	
	MSD_BLN_grid_outlier_rejection_new<<<MSD_conf->final_gridSize, MSD_conf->final_blockSize>>>(d_temp, d_MSD, MSD_conf->nBlocks_total+MSD_conf->address, OR_sigma_multiplier);
	
	#ifdef MSD_DEBUG
	cudaMemcpy(h_MSD, d_MSD, 3*sizeof(float), cudaMemcpyDeviceToHost); 
	printf("Output: Mean: %e, Standard deviation: %e; Elements:%zu;\n", h_MSD[0], h_MSD[1], (size_t) h_MSD[2]);
	printf("---------------------------<\n");
	#endif
	
	return(0);
}

//------------- MSD with outlier rejection
//---------------------------------------------------------------





//---------------------------------------------------------------
//------------- MSD with outlier rejection on grid

int MSD_grid_outlier_rejection(float *d_MSD, float *d_input, int CellDim_x, int CellDim_y, int nTimesamples, int nDMs, int offset, float multiplier){
	//---------> Task specific
	int GridSize_x, GridSize_y, x_steps, y_steps, nThreads;
	GridSize_x=(nTimesamples-offset)/CellDim_x;
	GridSize_y=nDMs/CellDim_y;
	x_steps=CellDim_x/WARP;
	if(CellDim_y<HALF_WARP) {
		y_steps  = 1;
		nThreads = WARP*CellDim_y;
	}
	else {
		nThreads = WARP*HALF_WARP;
		y_steps  = CellDim_y/HALF_WARP;
	}

	//---------> Initial phase
	dim3 gridSize(GridSize_x, GridSize_y, 1);
	dim3 blockSize(nThreads, 1, 1);

	//---------> Final phase
	dim3 final_gridSize(1, 1, 1);
	dim3 final_blockSize(WARP*WARP, 1, 1);

	//---------> Allocation of temporary memory
	float *d_output;
	cudaMalloc((void **) &d_output, GridSize_x*GridSize_y*3*sizeof(float));

	//---------> MSD
	MSD_init();
	MSD_BLN_grid_calculate_partials<<<gridSize,blockSize,nThreads*8>>>(d_input, d_output, x_steps, y_steps, nTimesamples, 0);
	MSD_BLN_grid_outlier_rejection<<<final_gridSize, final_blockSize>>>(d_output, d_MSD, GridSize_x*GridSize_y, (float) (CellDim_x*CellDim_y), multiplier);

	//---------> De-allocation of temporary memory
	cudaFree(d_output);
	
	return(1);
}

//------------- MSD with outlier rejection on grid
//---------------------------------------------------------------


//---------------------------------------------------------------
//------------- MSD plane profile

void Do_MSD_normal(float *d_MSD, float *d_input, float *d_MSD_workarea, int nTimesamples, int nDMs, int offset, float OR_sigma_multiplier, int enable_outlier_rejection){
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	if(enable_outlier_rejection){
		MSD_outlier_rejection(d_MSD, d_input, d_MSD_workarea, &conf, OR_sigma_multiplier);
	}
	else {
		MSD_normal(d_MSD, d_input, d_MSD_workarea, &conf);
	}
}

void Do_MSD_continuous(float *d_MSD, float *d_input, float *d_previous_partials, float *d_MSD_workarea, int nTimesamples, int nDMs, int offset, float OR_sigma_multiplier, int enable_outlier_rejection){
	MSD_Configuration conf(nTimesamples, nDMs, offset, 0);
	if(enable_outlier_rejection){
		MSD_outlier_rejection_continuous(d_MSD, d_input, d_previous_partials, d_MSD_workarea, &conf, OR_sigma_multiplier);
	}
	else {
		MSD_normal_continuous(d_MSD, d_input, d_previous_partials, d_MSD_workarea, &conf);
	}
}

inline void Do_MSD(float *d_MSD, float *d_input, float *d_previous_partials, float *d_MSD_workarea, int nTimesamples, int nDMs, int offset, float OR_sigma_multiplier, int enable_outlier_rejection, bool perform_continuous) {
	if(perform_continuous) Do_MSD_continuous(d_MSD, d_input, d_previous_partials, d_MSD_workarea, nTimesamples, nDMs, offset, OR_sigma_multiplier, enable_outlier_rejection);
	else Do_MSD_normal(d_MSD, d_input, d_MSD_workarea, nTimesamples, nDMs, offset, OR_sigma_multiplier, enable_outlier_rejection);
}


void MSD_plane_profile_debug(float *d_MSD, int DIT_value, int nTimesamples){
	float h_MSD[MSD_RESULTS_SIZE];
	checkCudaErrors(cudaMemcpy(h_MSD, d_MSD, MSD_RESULTS_SIZE*sizeof(float), cudaMemcpyDeviceToHost));
	printf("    DiT:%d; nTimesamples:%d; decimated_timesamples:%d; MSD:[%f; %f; %f]\n", (int) DIT_value, (int) nTimesamples, (int) (nTimesamples>>1), h_MSD[0], h_MSD[1], h_MSD[2]);
}


void MSD_of_input_plane(float *d_MSD_DIT, std::vector<int> *h_MSD_DIT_widths, float *d_input_data, float *d_MSD_DIT_previous, float *d_sudy, float *d_lichy, float *d_MSD_workarea, size_t nTimesamples, size_t nDMs, int nDecimations, int max_width_performed, float OR_sigma_multiplier, int enable_outlier_rejection, bool high_memory, bool perform_continuous, double *total_time, double *dit_time, double *MSD_time){
	GpuTimer timer, total_timer;
	double t_dit_time=0, t_MSD_time=0;
	int nRest;
	size_t decimated_timesamples;
	int DIT_value;

	
	total_timer.Start();
	//----------------------------------------------------------------------------------------
	//-------- DIT = 1
	DIT_value = 1;
	
	timer.Start();
	Do_MSD(d_MSD_DIT, d_input_data, d_MSD_DIT_previous, d_MSD_workarea, nTimesamples, nDMs, 0, OR_sigma_multiplier, enable_outlier_rejection, perform_continuous);
	timer.Stop();	t_MSD_time += timer.Elapsed();
	h_MSD_DIT_widths->push_back(DIT_value);
	#ifdef MSD_PLANE_DEBUG
	printf("    MSD format: [ mean ; StDev ; nElements ]\n");
	MSD_plane_profile_debug(d_MSD_DIT, DIT_value, nTimesamples);
	#endif
	//----------------------------------------------------------------------------------------
	
	checkCudaErrors(cudaGetLastError());
	
	//----------------------------------------------------------------------------------------
	//-------- DIT = 2
	DIT_value = DIT_value*2;
	
	if(high_memory){
		//printf("High memory: DIT=2 is not split\n");
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(d_input_data, d_lichy, nDMs, nTimesamples);
		decimated_timesamples = (nTimesamples>>1);
		timer.Stop();	t_dit_time += timer.Elapsed();
		
		timer.Start();
		Do_MSD(&d_MSD_DIT[MSD_RESULTS_SIZE], d_lichy, &d_MSD_DIT_previous[MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, enable_outlier_rejection, perform_continuous);
		timer.Stop();	t_MSD_time += timer.Elapsed();
		h_MSD_DIT_widths->push_back(DIT_value);
		
		#ifdef MSD_PLANE_DEBUG
		MSD_plane_profile_debug(&d_MSD_DIT[MSD_RESULTS_SIZE], DIT_value, decimated_timesamples);
		#endif
		
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(d_lichy, d_sudy, nDMs, decimated_timesamples);
		timer.Stop();	t_dit_time += timer.Elapsed();
	}
	else {
		//printf("Low memory: DIT=2 is split in two\n");
		// First decimation is split into two parts, that way we can lower the memory requirements for MSD_plane_profile
		// First half of the decimation
		int nDMs_half = (nDMs>>1);
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(d_input_data, d_lichy, nDMs_half, nTimesamples);
		decimated_timesamples = (nTimesamples>>1);
		timer.Stop();	t_dit_time += timer.Elapsed();

		timer.Start();
		Do_MSD_continuous(&d_MSD_DIT[MSD_RESULTS_SIZE], d_lichy, &d_MSD_DIT[2*MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs_half, nRest, OR_sigma_multiplier, enable_outlier_rejection);
		timer.Stop();	t_MSD_time += timer.Elapsed();
		
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(d_lichy, d_sudy, nDMs_half, decimated_timesamples);
		timer.Stop();	t_dit_time += timer.Elapsed();
		
		// second half of the decimation
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(&d_input_data[nDMs_half*nTimesamples], d_lichy, nDMs_half, nTimesamples);
		decimated_timesamples = (nTimesamples>>1);
		timer.Stop();	t_dit_time += timer.Elapsed();

		timer.Start();
		Do_MSD_continuous(&d_MSD_DIT[MSD_RESULTS_SIZE], d_lichy, &d_MSD_DIT[2*MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs_half, nRest, OR_sigma_multiplier, enable_outlier_rejection);
		timer.Stop();	t_MSD_time += timer.Elapsed();
		h_MSD_DIT_widths->push_back(DIT_value);
		
		timer.Start();
		nRest = GPU_DiT_v2_wrapper(d_lichy, &d_sudy[nDMs_half*(decimated_timesamples>>1)], nDMs_half, decimated_timesamples);
		timer.Stop();	t_dit_time += timer.Elapsed();
		
		#ifdef MSD_PLANE_DEBUG
		MSD_plane_profile_debug(&d_MSD_DIT[MSD_RESULTS_SIZE], DIT_value, decimated_timesamples);
		#endif
	}
	
	decimated_timesamples = (nTimesamples>>2);
	DIT_value = DIT_value*2;
	
	timer.Start();
	Do_MSD(&d_MSD_DIT[2*MSD_RESULTS_SIZE], d_sudy, &d_MSD_DIT_previous[2*MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, enable_outlier_rejection, perform_continuous);
	timer.Stop();	t_MSD_time += timer.Elapsed();
	h_MSD_DIT_widths->push_back(DIT_value);	
	
	#ifdef MSD_PLANE_DEBUG
	MSD_plane_profile_debug(&d_MSD_DIT[2*MSD_RESULTS_SIZE], DIT_value, decimated_timesamples);
	#endif
	//----------------------------------------------------------------------------------------
	
	checkCudaErrors(cudaGetLastError());
	
	//----------------------------------------------------------------------------------------
	//-------- DIT > 3
	for(size_t f=3; f<=nDecimations; f++){
		timer.Start();
		DIT_value = DIT_value*2;
		if(DIT_value<=max_width_performed){
			if(f%2==0){
				timer.Start();
				nRest = GPU_DiT_v2_wrapper(d_lichy, d_sudy, nDMs, decimated_timesamples);
				timer.Stop();	t_dit_time += timer.Elapsed();
				if(nRest<0) break;
				decimated_timesamples = (decimated_timesamples>>1);

				timer.Start();
				Do_MSD(&d_MSD_DIT[f*MSD_RESULTS_SIZE], d_sudy, &d_MSD_DIT_previous[f*MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, enable_outlier_rejection, perform_continuous);
				timer.Stop();	t_MSD_time += timer.Elapsed();
			}
			else {
				timer.Start();
				nRest = GPU_DiT_v2_wrapper(d_sudy, d_lichy, nDMs, decimated_timesamples);
				timer.Stop();	t_dit_time += timer.Elapsed();
				if(nRest<0) break;
				decimated_timesamples = (decimated_timesamples>>1);

				timer.Start();
				Do_MSD(&d_MSD_DIT[f*MSD_RESULTS_SIZE], d_lichy, &d_MSD_DIT_previous[f*MSD_RESULTS_SIZE], d_MSD_workarea, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, enable_outlier_rejection, perform_continuous);
				timer.Stop();	t_MSD_time += timer.Elapsed();
			}
			h_MSD_DIT_widths->push_back(DIT_value);
			
			#ifdef MSD_PLANE_DEBUG
				MSD_plane_profile_debug(&d_MSD_DIT[f*MSD_RESULTS_SIZE], DIT_value, decimated_timesamples);
			#endif
		}
		checkCudaErrors(cudaGetLastError());
	}
	//----------------------------------------------------------------------------------------
	
	checkCudaErrors(cudaGetLastError());
	
	//----------------------------------------------------------------------------------------
	//-------- Boxcar for last boxcar width if needed
	/*
	if(DIT_value<max_width_performed){
		DIT_value = (DIT_value>>1);
		decimated_timesamples = nTimesamples/DIT_value;
		int nTaps = max_width_performed/DIT_value;
		if(max_width_performed%DIT_value!=0) nTaps++;
		
		if(nDecimations%2==0){
			nRest = PPF_L1(d_lichy, d_sudy, nDMs, decimated_timesamples, nTaps);

			checkCudaErrors(cudaGetLastError());
			
			timer.Start();
			Do_MSD(&d_MSD_DIT[(nDecimations+1)*MSD_RESULTS_SIZE], d_sudy, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, MSD_type);
			timer.Stop();	MSD_time += timer.Elapsed();
		}
		else {
			nRest = PPF_L1(d_sudy, d_lichy, nDMs, decimated_timesamples, nTaps);
			
			checkCudaErrors(cudaGetLastError());
			
			timer.Start();
			Do_MSD(&d_MSD_DIT[(nDecimations+1)*MSD_RESULTS_SIZE], d_lichy, decimated_timesamples, nDMs, nRest, OR_sigma_multiplier, MSD_type);
			timer.Stop();	MSD_time += timer.Elapsed();
		}
		h_MSD_DIT_widths->push_back(DIT_value*nTaps);

		#ifdef GPU_ANALYSIS_DEBUG
			printf("    Performing additional boxcar: nTaps: %d; max_width_performed: %d; DIT_value/2: %d;\n", nTaps, max_width_performed, DIT_value);
			checkCudaErrors(cudaMemcpy(h_MSD, &d_MSD_DIT[(nDecimations+1)*MSD_RESULTS_SIZE], MSD_RESULTS_SIZE*sizeof(float), cudaMemcpyDeviceToHost));
			printf("    DIT: %d; MSD:[%f; %f; %f]\n", DIT_value*nTaps, h_MSD[0], h_MSD[1], h_MSD[2]);
		#endif		
	}
	*/
	//----------------------------------------------------------------------------------------
	
	checkCudaErrors(cudaGetLastError());
	
	total_timer.Stop();
	(*total_time) = total_timer.Elapsed();
	(*dit_time) = t_dit_time;
	(*MSD_time) = t_MSD_time;
	
	#ifdef GPU_PARTIAL_TIMER
		printf("    MSD of input plane: Total time: %f ms; DiT time: %f ms; MSD time: %f ms;\n", (*total_time), (*dit_time), (*MSD_time));
	#endif
}


void MSD_Interpolate_linear(float *mean, float *StDev, float desired_width, float *h_MSD_DIT, std::vector<int> *h_MSD_DIT_widths){
	int MSD_DIT_size = h_MSD_DIT_widths->size();
	int position = (int) floorf(log2f((float) desired_width));
	
	float width1 = h_MSD_DIT_widths->operator[](position);
	float mean1 = h_MSD_DIT[(position)*MSD_RESULTS_SIZE];
	float StDev1 = h_MSD_DIT[(position)*MSD_RESULTS_SIZE +1];
	
	if(position == MSD_DIT_size-1 && width1==(int) desired_width) {
		(*mean) = mean1;
		(*StDev) = StDev1;
	}
	else {
		float width2 = h_MSD_DIT_widths->operator[](position+1);
		float distance_in_width = width2 - width1;
		
		float mean2 = h_MSD_DIT[(position+1)*MSD_RESULTS_SIZE];
		float distance_in_mean = mean2 - mean1;
		
		float StDev2 = h_MSD_DIT[(position+1)*MSD_RESULTS_SIZE +1];
		float distance_in_StDev = StDev2 - StDev1;
	
		(*mean) = mean1 + (distance_in_mean/distance_in_width)*((float) desired_width - width1);
		(*StDev) = StDev1 + (distance_in_StDev/distance_in_width)*((float) desired_width - width1);
	}
}


void MSD_Interpolate_square(float *mean, float *StDev, float desired_width, float *h_MSD_DIT, std::vector<int> *h_MSD_DIT_widths){
	int MSD_DIT_size = h_MSD_DIT_widths->size();
	int position = (int) floorf(log2f((float) desired_width));
	
	if(position == MSD_DIT_size-2) position--;
	if(position == MSD_DIT_size-1 && h_MSD_DIT_widths->operator[](position)==(int) desired_width) {
		(*mean)  = h_MSD_DIT[(position)*MSD_RESULTS_SIZE];
		(*StDev) = h_MSD_DIT[(position)*MSD_RESULTS_SIZE +1];
	}
	else {
		float w = desired_width;
		
		float w0 = h_MSD_DIT_widths->operator[](position);
		float mean0  = h_MSD_DIT[(position)*MSD_RESULTS_SIZE];
		float StDev0 = h_MSD_DIT[(position)*MSD_RESULTS_SIZE +1];
		
		float w1 = h_MSD_DIT_widths->operator[](position+1);
		float mean1  = h_MSD_DIT[(position+1)*MSD_RESULTS_SIZE];
		float StDev1 = h_MSD_DIT[(position+1)*MSD_RESULTS_SIZE +1];
		
		float w2 = h_MSD_DIT_widths->operator[](position+2);
		float mean2  = h_MSD_DIT[(position+2)*MSD_RESULTS_SIZE];
		float StDev2 = h_MSD_DIT[(position+2)*MSD_RESULTS_SIZE +1];
		
		float a0 = ((w - w1)*(w - w2))/((w0 - w1)*(w0 - w2));
		float a1 = ((w - w0)*(w - w2))/((w1 - w0)*(w1 - w2));
		float a2 = ((w - w0)*(w - w1))/((w2 - w0)*(w2 - w1));
		
		(*mean)  = a0*mean0 + a1*mean1 + a2*mean2;
		(*StDev) = a0*StDev0 + a1*StDev1 + a2*StDev2;
	}
}


void MSD_Export_plane(const char *filename, float *h_MSD_DIT, std::vector<int> *h_MSD_DIT_widths, float *h_MSD_interpolated, std::vector<int> *h_boxcar_widths, int max_width_performed) {
	char str[200];
	std::ofstream FILEOUT;
	int MSD_INTER_SIZE = 2;
	
	sprintf(str,"%s_DIT.dat", filename);
	FILEOUT.open (str, std::ofstream::out);
	for(size_t f=0; f<(int) h_MSD_DIT_widths->size(); f++){
		FILEOUT << (int) h_MSD_DIT_widths->operator[](f) << " " << h_MSD_DIT[f*MSD_RESULTS_SIZE] << " " << h_MSD_DIT[f*MSD_RESULTS_SIZE + 1] << std::endl;
	}
	FILEOUT.close();
	
	sprintf(str,"%s_Interpolated.dat", filename);
	FILEOUT.open (str, std::ofstream::out);
	for(size_t f=0; f<(int) h_boxcar_widths->size(); f++){
		if(h_boxcar_widths->operator[](f)<=max_width_performed)
			FILEOUT << (int) h_boxcar_widths->operator[](f) << " " << h_MSD_interpolated[f*MSD_INTER_SIZE] << " " << h_MSD_interpolated[f*MSD_INTER_SIZE + 1] << std::endl;
	}
	FILEOUT.close();
}


void MSD_Interpolate_values(float *d_MSD_interpolated, float *d_MSD_DIT, std::vector<int> *h_MSD_DIT_widths, int nMSDs, std::vector<int> *h_boxcar_widths, int max_width_performed, const char *filename){
	#ifdef GPU_PARTIAL_TIMER
	GpuTimer timer;
	timer.Start();
	#endif
	
	int MSD_INTER_SIZE = 2;
	float *h_MSD_DIT, *h_MSD_interpolated;
	int nWidths = (int) h_boxcar_widths->size();
	h_MSD_DIT = new float[nMSDs*MSD_RESULTS_SIZE];
	h_MSD_interpolated = new float[nWidths*MSD_INTER_SIZE];
	
	checkCudaErrors(cudaMemcpy(h_MSD_DIT, d_MSD_DIT, nMSDs*MSD_RESULTS_SIZE*sizeof(float), cudaMemcpyDeviceToHost));
	
	for(int f=0; f<nWidths; f++){
		if(h_boxcar_widths->operator[](f)<=max_width_performed) {
			float mean, StDev;
			MSD_Interpolate_linear(&mean, &StDev, (float) h_boxcar_widths->operator[](f), h_MSD_DIT, h_MSD_DIT_widths);
			h_MSD_interpolated[f*MSD_INTER_SIZE] = mean;
			h_MSD_interpolated[f*MSD_INTER_SIZE+1] = StDev;
		}
	}
	
	#ifdef MSD_PLANE_EXPORT
		MSD_Export_plane(filename, h_MSD_DIT, h_MSD_DIT_widths, h_MSD_interpolated, h_boxcar_widths, max_width_performed);
	#endif
	
	checkCudaErrors(cudaMemcpy(d_MSD_interpolated, h_MSD_interpolated, nWidths*MSD_INTER_SIZE*sizeof(float), cudaMemcpyHostToDevice));
	
	delete[] h_MSD_DIT;
	delete[] h_MSD_interpolated;
	
	#ifdef GPU_PARTIAL_TIMER
	timer.Stop();
	printf("    Interpolation step took %f ms;\n", timer.Elapsed());
	#endif
}

//-------------------------------------------------------------------------<

void Get_MSD_plane_profile_memory_requirements(size_t *MSD_profile_size_in_bytes, size_t *MSD_DIT_profile_size_in_bytes, size_t *workarea_size_in_bytes, size_t primary_dimension, size_t secondary_dimension, std::vector<int> *boxcar_widths) {
	// temporary work area for decimations. We need 2*1/4 = 1/2.
	size_t t_wsib = (primary_dimension*secondary_dimension*sizeof(float))/2;
	printf("Pd: %zu; Sd: %zu;\n", primary_dimension, secondary_dimension);
	printf("temporary storage for data: %zu bytes = %zu floats;\n", t_wsib, t_wsib/4);
	
	// temporary storage for MSD values of decimated input data
	int max_boxcar_width = boxcar_widths->operator[](boxcar_widths->size()-1);
	int nDecimations = ((int) floorf(log2f((float)max_boxcar_width))) + 2;
	t_wsib = t_wsib + nDecimations*MSD_RESULTS_SIZE*sizeof(float);
	printf("Size of DIT MSDs: %d elements = %d float = %d bytes\n", nDecimations, nDecimations*MSD_RESULTS_SIZE, nDecimations*MSD_RESULTS_SIZE*sizeof(float));
	
	// temporary storage for calculation of MSD. We have to choose the maximum from all possible variants.
	size_t decimated_pd = primary_dimension;
	int max_nBlocks = 0;
	for(int f=0; f<nDecimations; f++){
		MSD_Configuration conf(decimated_pd, secondary_dimension, 0, 0);
		if(conf.nBlocks_total>max_nBlocks) max_nBlocks = conf.nBlocks_total;
		decimated_pd = (decimated_pd>>1);
	}
	t_wsib = t_wsib + max_nBlocks*MSD_PARTIAL_SIZE*sizeof(float);
	printf("max_nBlocks: %d blocks = %d float = %d bytes\n", max_nBlocks, max_nBlocks*MSD_PARTIAL_SIZE, max_nBlocks*MSD_PARTIAL_SIZE*sizeof(float));
	
	(*workarea_size_in_bytes) = t_wsib;
	(*MSD_profile_size_in_bytes) = boxcar_widths->size()*2*sizeof(float);
	(*MSD_DIT_profile_size_in_bytes) = nDecimations*MSD_PARTIAL_SIZE*sizeof(float);
}


// TODO:
//		Make it fail reasonably, which means if max_boxcar_width = 1 calculate only MSD for given plane and omit DIT completely
//		Add checks when StDev blows up because of too much DIT
//		Add checks if there is enough timesamples to do DIT.
// Note: By separating DIT = 2 into two parts we slightly decreasing precision if compared to non spit case, because outlier rejection has fewer points to work with. This could be a problem if we have a plane small enough to fit into memory but we still plit it in two.
//		Add branch that would not split DIT=2 if there is enough memory. 
void MSD_plane_profile(float *d_MSD_interpolated, float *d_input_data, float *d_MSD_DIT_previous, float *workarea, bool high_memory, size_t primary_dimension, size_t secondary_dimension, std::vector<int> *boxcar_widths, float tstart, float dm_low, float dm_high, float OR_sigma_multiplier, int enable_outlier_rejection, bool perform_continuous, double *total_time, double *dit_time, double *MSD_time){
	int boxcar_widths_size = (int) boxcar_widths->size();
	int max_boxcar_width = boxcar_widths->operator[](boxcar_widths_size-1);
	int nDecimations = ((int) floorf(log2f((float)max_boxcar_width))) + 1;
	int nDIT_widths = nDecimations + 1;
	std::vector<int> h_MSD_DIT_widths;
	
	size_t datasize = primary_dimension*secondary_dimension;
	float *d_sudy, *d_lichy, *d_MSD_DIT, *d_MSD_workarea; 
	d_sudy = workarea;
	d_lichy = &workarea[datasize/4];
	d_MSD_DIT = &workarea[datasize/2];
	d_MSD_workarea = &workarea[datasize/2 + (nDecimations+1)*MSD_RESULTS_SIZE];
	
	MSD_of_input_plane(d_MSD_DIT, &h_MSD_DIT_widths, d_input_data, d_MSD_DIT_previous, d_sudy, d_lichy, d_MSD_workarea, primary_dimension, secondary_dimension, nDecimations, max_boxcar_width, OR_sigma_multiplier, enable_outlier_rejection, high_memory, perform_continuous, total_time, dit_time, MSD_time);
	
	#ifdef MSD_PLANE_DEBUG
		printf("    Number of calculated MSD values: %d; number of interpolated MSD values: %d;\n",nDIT_widths, boxcar_widths_size);
	#endif
	
	char filename[100];
	sprintf(filename,"MSD_plane_profile_i_test-t_%.2f-dm_%.2f-%.2f", tstart, dm_low, dm_high);
	MSD_Interpolate_values(d_MSD_interpolated, d_MSD_DIT, &h_MSD_DIT_widths, nDIT_widths, boxcar_widths, max_boxcar_width, filename);
}

//------------- MSD plane profile
//---------------------------------------------------------------









