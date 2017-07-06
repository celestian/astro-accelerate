#include "headers/headers_mains.h"

#include <helper_cuda.h>

#include "headers/device_bin.h"
#include "headers/device_init.h"
#include "headers/device_dedisperse.h"
#include "headers/device_dedispersion_kernel.h"
#include "headers/device_zero_dm.h"
#include "headers/device_zero_dm_outliers.h"
#include "headers/device_rfi.h"


#include "headers/device_SPS_inplace_kernel.h" //Added by KA
#include "headers/device_SPS_inplace.h" //Added by KA
#include "headers/device_MSD_BLN_grid.h" //Added by KA
#include "headers/device_MSD_BLN_pw.h" //Added by KA
//#include "headers/device_MSD_BLN_pw_dp.h" //Added by KA
#include "headers/device_MSD_grid.h" //Added by KA
#include "headers/device_MSD_plane.h" //Added by KA
#include "headers/device_MSD_limited.h" //Added by KA
#include "headers/device_SNR_limited.h" //Added by KA
#include "headers/device_SPS_long.h" //Added by KA
#include "headers/device_threshold.h" //Added by KA
#include "headers/device_single_FIR.h" //Added by KA
#include "headers/device_analysis.h" //Added by KA

#include "headers/device_peak_find.h" //Added by KA

#include "headers/device_load_data.h"
#include "headers/device_corner_turn.h"
#include "headers/device_save_data.h"
#include "headers/host_acceleration.h"
#include "headers/host_allocate_memory.h"
#include "headers/host_analysis.h"
#include "headers/host_periods.h"
#include "headers/host_debug.h"
#include "headers/host_get_file_data.h"
#include "headers/host_get_recorded_data.h"
#include "headers/host_get_user_input.h"
#include "headers/host_help.h"
#include "headers/host_rfi.h"
#include "headers/host_stratagy.h"
#include "headers/host_write_file.h"

// fdas
#include "headers/device_acceleration_fdas.h"

#include "headers/host_main_function.h"

#include "headers/params.h"

#include "timer.h"

void main_function
	(
	int argc,
	char* argv[],
	// Internal code variables
	// File pointers
	FILE *fp,
	// Counters and flags
	int i,
	int t,
	int dm_range,
	int range,
	int enable_debug,
	int enable_analysis,
	int enable_acceleration,
	int enable_output_ffdot_plan,
	int enable_output_fdas_list,
	int enable_periodicity,
	int output_dmt,
	int enable_zero_dm,
	int enable_zero_dm_with_outliers,
	int enable_rfi,
	int enable_sps_baselinenoise,
	int enable_fdas_custom_fft,
	int enable_fdas_inbin,
	int enable_fdas_norm,
	int *inBin,
	int *outBin,
	int *ndms,
	int maxshift,
	int max_ndms,
	int max_samps,
	int num_tchunks,
	int total_ndms,
	int multi_file,
	float max_dm,
	// Memory sizes and pointers
  size_t inputsize,
  size_t outputsize,
	size_t gpu_inputsize,
	size_t gpu_outputsize,
	size_t gpu_memory,
  unsigned short  *input_buffer,
	float ***output_buffer,
	unsigned short  *d_input1,
	float *d_output1,
	unsigned short  *d_input2,
	float *d_output2,
	float *dmshifts,
	float *user_dm_low,
	float *user_dm_high,
	float *user_dm_step,
	float *dm_low,
	float *dm_high,
	float *dm_step,
	// Telescope parameters
	int nchans,
	int nsamp,
	int nbits,
	int nsamples,
	int nifs,
	int **t_processed,
	int nboots,
	int ntrial_bins,
	int navdms,
	int nsearch,
	float aggression,
	float narrow,
	float wide,
	int	maxshift_original,
	double	tsamp_original,
	long int inc,
	float tstart,
	float tstart_local,
	float tsamp,
	float fch1,
	float foff,
	// Analysis variables
	float power,
	float sigma_cutoff,
	float sigma_constant,
	float max_boxcar_width_in_sec,
	clock_t start_time,
	int candidate_algorithm,
	int nb_selected_dm,
	float *selected_dm_low,
	float *selected_dm_high,
	int analysis_debug,
	int failsafe
	)
{

	// Initialise the GPU.	
	init_gpu(argc, argv, enable_debug, &gpu_memory);
	if(enable_debug == 1) debug(2, start_time, range, outBin, enable_debug, enable_analysis, output_dmt, multi_file, sigma_cutoff, power, max_ndms, user_dm_low, user_dm_high,
	user_dm_step, dm_low, dm_high, dm_step, ndms, nchans, nsamples, nifs, nbits, tsamp, tstart, fch1, foff, maxshift, max_dm, nsamp, gpu_inputsize, gpu_outputsize, inputsize, outputsize);

	checkCudaErrors(cudaGetLastError());
	
	// Calculate the dedispersion stratagy.
	stratagy(&maxshift, &max_samps, &num_tchunks, &max_ndms, &total_ndms, &max_dm, power, nchans, nsamp, fch1, foff, tsamp, range, user_dm_low, user_dm_high, user_dm_step,
                 &dm_low, &dm_high, &dm_step, &ndms, &dmshifts, inBin, &t_processed, &gpu_memory, Get_memory_requirement_of_SPS());
	if(enable_debug == 1) debug(4, start_time, range, outBin, enable_debug, enable_analysis, output_dmt, multi_file, sigma_cutoff, power, max_ndms, user_dm_low, user_dm_high,
	user_dm_step, dm_low, dm_high, dm_step, ndms, nchans, nsamples, nifs, nbits, tsamp, tstart, fch1, foff, maxshift, max_dm, nsamp, gpu_inputsize, gpu_outputsize, inputsize, outputsize);

	checkCudaErrors(cudaGetLastError());
	
	// Allocate memory on host and device.
	allocate_memory_cpu_output_stream(&fp, gpu_memory, maxshift, num_tchunks, max_ndms, total_ndms, nsamp, nchans, nbits, range, ndms, t_processed, &input_buffer, &output_buffer, &d_input1, &d_output1,
                        &gpu_inputsize, &gpu_outputsize, &inputsize, &outputsize);
	if(enable_debug == 1) debug(5, start_time, range, outBin, enable_debug, enable_analysis, output_dmt, multi_file, sigma_cutoff, power, max_ndms, user_dm_low, user_dm_high,
	user_dm_step, dm_low, dm_high, dm_step, ndms, nchans, nsamples, nifs, nbits, tsamp, tstart, fch1, foff, maxshift, max_dm, nsamp, gpu_inputsize, gpu_outputsize, inputsize, outputsize);

	checkCudaErrors(cudaGetLastError());
	
	// Allocate memory on host and device.
	allocate_memory_gpu(&fp, gpu_memory, maxshift, num_tchunks, max_ndms, total_ndms, nsamp, nchans, nbits, range, ndms, t_processed, &input_buffer, &output_buffer, &d_input1, &d_output1,
			            &d_input2, &d_output2, &gpu_inputsize, &gpu_outputsize, &inputsize, &outputsize);
	if(enable_debug == 1) debug(5, start_time, range, outBin, enable_debug, enable_analysis, output_dmt, multi_file, sigma_cutoff, power, max_ndms, user_dm_low, user_dm_high,
	user_dm_step, dm_low, dm_high, dm_step, ndms, nchans, nsamples, nifs, nbits, tsamp, tstart, fch1, foff, maxshift, max_dm, nsamp, gpu_inputsize, gpu_outputsize, inputsize, outputsize);

	checkCudaErrors(cudaGetLastError());
	
	// Clip RFI

	//rfi(nsamp, nchans, &input_buffer);
	/*
	 FILE	*fp_o;

	 if ((fp_o=fopen("rfi_clipped.dat", "wb")) == NULL) {
	 fprintf(stderr, "Error opening output file!\n");
	 exit(0);
	 }
	 fwrite(input_buffer, nchans*nsamp*sizeof(unsigned short), 1, fp_o);
	 */

	// Create streams
	cudaStream_t stream1, stream2;
	cudaStreamCreate(&stream1);
	cudaStreamCreate(&stream2);

	GpuTimer timer;
	timer.Start();

	tsamp_original = tsamp;
	maxshift_original = maxshift;

	//float *out_tmp;
	//out_tmp = (float *) malloc(( t_processed[0][0] + maxshift ) * max_ndms * sizeof(float));
	//memset(out_tmp, 0.0f, t_processed[0][0] + maxshift * max_ndms * sizeof(float));

	for (t = 0; t < num_tchunks; t++)
	{
		printf("\nt_processed:\t%d, %d", t_processed[0][t], t);
		checkCudaErrors(cudaGetLastError());

		load_data(-1, inBin, d_input1, &input_buffer[(long int) ( inc * nchans )], t_processed[0][t], maxshift, nchans, dmshifts);
		checkCudaErrors(cudaGetLastError());
		
		if (enable_zero_dm)
			zero_dm(d_input1, nchans, t_processed[0][t]+maxshift);
		checkCudaErrors(cudaGetLastError());
		
		if (enable_zero_dm_with_outliers)
			zero_dm_outliers(d_input1, nchans, t_processed[0][t]+maxshift);
		checkCudaErrors(cudaGetLastError());
	
		corner_turn(d_input1, d_output1, nchans, t_processed[0][t] + maxshift);
		checkCudaErrors(cudaGetLastError());
		
		if (enable_rfi)
 			rfi_gpu(d_input1, nchans, t_processed[0][t]+maxshift);
		checkCudaErrors(cudaGetLastError());

		/******************* streams start here ******************/
		printf("\n\n%f\t%f\t%f\t%d", dm_low[0], dm_high[0], dm_step[0], ndms[0]), fflush(stdout);
		printf("\nAmount of telescope time processed: %f", tstart_local);
		maxshift = maxshift_original / inBin[0];
		checkCudaErrors(cudaGetLastError());
		load_data_stream(0, inBin, d_input1, &input_buffer[(long int) ( inc * nchans )], t_processed[0][t], maxshift, nchans, dmshifts, stream1);
		checkCudaErrors(cudaGetLastError());
		// no bin_gpu needed here
		// dedispersion stream 1
		dedisperse_stream(0, t_processed[0][t], inBin, dmshifts, d_input1, d_output1, nchans, ( t_processed[0][t] + maxshift ), maxshift, &tsamp, dm_low, dm_high, dm_step, ndms, nbits, failsafe, stream1);
		checkCudaErrors(cudaGetLastError());

		cudaStreamSynchronize(stream1);
		// device to host stream 1
		if ( (enable_acceleration == 1) || (analysis_debug ==1) )
		{
			for (int k = 0; k < ndms[0]; k++)
				save_data_offset_stream(d_output1, k * t_processed[0][t], output_buffer[0][k], inc / inBin[0], sizeof(float) * t_processed[0][t], stream1);
		}
		
		int oldBin = 1;
		for (dm_range = 1; dm_range < range; dm_range+=2)
		{
			printf("\n\n%f\t%f\t%f\t%d", dm_low[dm_range], dm_high[dm_range], dm_step[dm_range], ndms[dm_range]), fflush(stdout);
			printf("\nAmount of telescope time processed: %f", tstart_local);
			maxshift = maxshift_original / inBin[dm_range];
			checkCudaErrors(cudaGetLastError());
			load_data_stream(dm_range, inBin, d_input1, &input_buffer[(long int) ( inc * nchans )], t_processed[dm_range][t], maxshift, nchans, dmshifts, stream2);
			checkCudaErrors(cudaGetLastError());

			// bin stream2
			if (inBin[dm_range] > oldBin)
			{
				bin_gpu_stream(d_input1, d_output1, nchans, t_processed[dm_range][t] + maxshift * inBin[dm_range], stream2);
				( tsamp ) = ( tsamp ) * 2.0f;
			}
			checkCudaErrors(cudaGetLastError());
			// dedispersion stream2
			dedisperse_stream(dm_range, t_processed[dm_range][t], inBin, dmshifts, d_input1, d_output1, nchans, ( t_processed[dm_range][t] + maxshift ), maxshift, &tsamp, dm_low, dm_high, dm_step, ndms, nbits, failsafe, stream2);
			checkCudaErrors(cudaGetLastError());

			// sps stream 1
			if (enable_analysis == 1)
			{
				if (analysis_debug == 1)
				{
					float *out_tmp;
					gpu_outputsize = ndms[dm_range-1] * ( t_processed[dm_range-1][t] ) * sizeof(float);
					out_tmp = (float *) malloc(( t_processed[0][0] + maxshift ) * max_ndms * sizeof(float));
					memset(out_tmp, 0.0f, t_processed[0][0] + maxshift * max_ndms * sizeof(float));
					save_data(d_output1, out_tmp, gpu_outputsize);
					analysis_CPU(dm_range-1, tstart_local, t_processed[dm_range-1][t], (t_processed[dm_range-1][t]+maxshift), nchans, maxshift, max_ndms, ndms, outBin, sigma_cutoff, out_tmp,dm_low, dm_high, dm_step, tsamp, max_boxcar_width_in_sec);
					free(out_tmp);
				}
				else
				{
					float *h_peak_list;
					size_t max_peak_size;
					size_t peak_pos;
					max_peak_size = (size_t) ( ndms[dm_range-1]*t_processed[dm_range-1][t]/2 );
					//h_peak_list   = (float*) malloc(max_peak_size*4*sizeof(float));
					cudaMallocHost((void**)&(h_peak_list), max_peak_size*4*sizeof(float));
					peak_pos=0;
					analysis_GPU_stream(h_peak_list, &peak_pos, max_peak_size, dm_range-1, tstart_local, t_processed[dm_range-1][t], inBin[dm_range-1], outBin[dm_range-1], &maxshift, max_ndms, ndms, sigma_cutoff, sigma_constant, max_boxcar_width_in_sec, d_output1, dm_low, dm_high, dm_step, tsamp, candidate_algorithm, enable_sps_baselinenoise, stream1);
					cudaFreeHost(h_peak_list);
				}
			}
			oldBin = inBin[dm_range-1];

			cudaStreamSynchronize(stream2);
			// device to host stream2
			if ( (enable_acceleration == 1) || (analysis_debug ==1) )
			{
				for (int k = 0; k < ndms[dm_range]; k++)
					save_data_offset_stream(d_output1, k * t_processed[dm_range][t], output_buffer[dm_range][k], inc / inBin[dm_range], sizeof(float) * t_processed[dm_range][t], stream2);
			}
			checkCudaErrors(cudaGetLastError());
			
			if (dm_range+1<range)
			{
				printf("\n\n%f\t%f\t%f\t%d", dm_low[dm_range+1], dm_high[dm_range+1], dm_step[dm_range+1], ndms[dm_range+1]), fflush(stdout);
				printf("\nAmount of telescope time processed: %f", tstart_local);
				maxshift = maxshift_original / inBin[dm_range+1];

				load_data_stream(dm_range+1, inBin, d_input1, &input_buffer[(long int) ( inc * nchans )], t_processed[dm_range+1][t], maxshift, nchans, dmshifts, stream2);
				checkCudaErrors(cudaGetLastError());

				// bin stream1
				if (inBin[dm_range+1] > oldBin)
				{
					bin_gpu_stream(d_input1, d_output1, nchans, t_processed[dm_range+1][t] + maxshift * inBin[dm_range+1], stream1);
					( tsamp ) = ( tsamp ) * 2.0f;
				}
				// dedispersion stream1
				if ((dm_range+1)<range)
				{
					dedisperse_stream(dm_range+1, t_processed[dm_range+1][t], inBin, dmshifts, d_input1, d_output1, nchans, ( t_processed[dm_range+1][t] + maxshift ), maxshift, &tsamp, dm_low, dm_high, dm_step, ndms, nbits, failsafe, stream1);
					checkCudaErrors(cudaGetLastError());
				}
			}
			// sps stream2
			if (enable_analysis == 1)
			{
				if (analysis_debug == 1)
				{
					float *out_tmp;
					gpu_outputsize = ndms[dm_range] * ( t_processed[dm_range][t] ) * sizeof(float);
					out_tmp = (float *) malloc(( t_processed[0][0] + maxshift ) * max_ndms * sizeof(float));
					memset(out_tmp, 0.0f, t_processed[0][0] + maxshift * max_ndms * sizeof(float));
					save_data(d_output1, out_tmp, gpu_outputsize);
					analysis_CPU(dm_range, tstart_local, t_processed[dm_range][t], (t_processed[dm_range][t]+maxshift), nchans, maxshift, max_ndms, ndms, outBin, sigma_cutoff, out_tmp,dm_low, dm_high, dm_step, tsamp, max_boxcar_width_in_sec);
					free(out_tmp);
				}
				else
				{
					float *h_peak_list;
					size_t max_peak_size;
					size_t peak_pos;
					max_peak_size = (size_t) ( ndms[dm_range]*t_processed[dm_range][t]/2 );
					cudaMallocHost((void**)&(h_peak_list), max_peak_size*4*sizeof(float));

					peak_pos=0;
					analysis_GPU_stream(h_peak_list, &peak_pos, max_peak_size, dm_range, tstart_local, t_processed[dm_range][t], inBin[dm_range], outBin[dm_range], &maxshift, max_ndms, ndms, sigma_cutoff, sigma_constant, max_boxcar_width_in_sec, d_output1, dm_low, dm_high, dm_step, tsamp, candidate_algorithm, enable_sps_baselinenoise, stream2);

					cudaFreeHost(h_peak_list);
				}
			}
			oldBin = inBin[dm_range];

			cudaStreamSynchronize(stream1);
			// device to host stream1
			if ( (enable_acceleration == 1) || (analysis_debug ==1) )
			{
				for (int k = 0; k < ndms[dm_range+1]; k++)
					save_data_offset_stream(d_output1, k * t_processed[dm_range+1][t], output_buffer[dm_range+1][k], inc / inBin[dm_range+1], sizeof(float) * t_processed[dm_range+1][t], stream1);
			}
			checkCudaErrors(cudaGetLastError());
		}

		// sps stream1
		if((range%2==1) && (enable_analysis==1))
		{
			if (analysis_debug == 1)
			{
				float *out_tmp;
				gpu_outputsize = ndms[range-1] * ( t_processed[range-1][t] ) * sizeof(float);
				out_tmp = (float *) malloc(( t_processed[0][0] + maxshift ) * max_ndms * sizeof(float));
				memset(out_tmp, 0.0f, t_processed[0][0] + maxshift * max_ndms * sizeof(float));
				save_data(d_output1, out_tmp, gpu_outputsize);
				analysis_CPU(range-1, tstart_local, t_processed[range-1][t], (t_processed[range-1][t]+maxshift), nchans, maxshift, max_ndms, ndms, outBin, sigma_cutoff, out_tmp,dm_low, dm_high, dm_step, tsamp, max_boxcar_width_in_sec);
				free(out_tmp);
			}
			else
			{
				float *h_peak_list;
				size_t max_peak_size;
				size_t peak_pos;
				max_peak_size = (size_t) ( ndms[range-1]*t_processed[range-1][t]/2 );
				cudaMallocHost((void**)&(h_peak_list), max_peak_size*4*sizeof(float));
				peak_pos=0;
				analysis_GPU_stream(h_peak_list, &peak_pos, max_peak_size, range-1, tstart_local, t_processed[range-1][t], inBin[range-1], outBin[range-1], &maxshift, max_ndms, ndms, sigma_cutoff, sigma_constant, max_boxcar_width_in_sec, d_output1, dm_low, dm_high, dm_step, tsamp, candidate_algorithm, enable_sps_baselinenoise, stream1);
				cudaFreeHost(h_peak_list);
			}
		}


		/******************* end of stream ******************/

		inc = inc + t_processed[0][t];
		printf("\nINC:\t%ld", inc);
		tstart_local = ( tsamp_original * inc );
		tsamp = tsamp_original;
		maxshift = maxshift_original;
	}

	timer.Stop();
	float time = timer.Elapsed() / 1000;

	printf("\n\n === OVERALL DEDISPERSION THROUGHPUT INCLUDING SYNCS AND DATA TRANSFERS ===\n");

	printf("\n(Performed Brute-Force Dedispersion: %g (GPU estimate)",  time);
	printf("\nAmount of telescope time processed: %f", tstart_local);
	printf("\nNumber of samples processed: %ld", inc);
	printf("\nReal-time speedup factor: %lf", ( tstart_local ) / time);

	cudaFree(d_input1);
	cudaFree(d_output1);
	//free(out_tmp);
	cudaFreeHost(input_buffer);
	cudaStreamDestroy(stream1);
	cudaStreamDestroy(stream2);

	double time_processed = ( tstart_local ) / tsamp_original;
	double dm_t_processed = time_processed * total_ndms;
	double all_processed = dm_t_processed * nchans;
	printf("\nGops based on %.2lf ops per channel per tsamp: %f", NOPS, ( ( NOPS * all_processed ) / ( time ) ) / 1000000000.0);
	int num_reg = SNUMREG;
	float num_threads = total_ndms * ( t_processed[0][0] ) / ( num_reg );
	float data_size_loaded = ( num_threads * nchans * sizeof(ushort) ) / 1000000000;
	float time_in_sec = time;
	float bandwidth = data_size_loaded / time_in_sec;
	printf("\nDevice global memory bandwidth in GB/s: %f", bandwidth);
	printf("\nDevice shared memory bandwidth in GB/s: %f", bandwidth * ( num_reg ));
	float size_gb = ( nchans * ( t_processed[0][0] ) * sizeof(float) * 8 ) / 1000000000.0;
	printf("\nTelescope data throughput in Gb/s: %f", size_gb / time_in_sec);

	if (enable_periodicity == 1)
	{
		//
		GpuTimer timer;
		timer.Start();
		//
		periodicity(range, nsamp, max_ndms, inc, nboots, ntrial_bins, navdms, narrow, wide, nsearch, aggression, sigma_cutoff, output_buffer, ndms, inBin, dm_low, dm_high, dm_step, tsamp_original);
		//
		timer.Stop();
		float time = timer.Elapsed()/1000;
		printf("\n\n === OVERALL PERIODICITY THROUGHPUT INCLUDING SYNCS AND DATA TRANSFERS ===\n");

		printf("\nPerformed Peroidicity Location: %f (GPU estimate)", time);
		printf("\nAmount of telescope time processed: %f", tstart_local);
		printf("\nNumber of samples processed: %ld", inc);
		printf("\nReal-time speedup factor: %f", ( tstart_local ) / ( time ));
	}

	if (enable_acceleration == 1)
	{
		// Input needed for fdas is output_buffer which is DDPlan
		// Assumption: gpu memory is free and available
		//
		GpuTimer timer;
		timer.Start();
		// acceleration(range, nsamp, max_ndms, inc, nboots, ntrial_bins, navdms, narrow, wide, nsearch, aggression, sigma_cutoff, output_buffer, ndms, inBin, dm_low, dm_high, dm_step, tsamp_original);
		acceleration_fdas(range, nsamp, max_ndms, inc, nboots, ntrial_bins, navdms, narrow, wide, nsearch, aggression, sigma_cutoff,
						  output_buffer, ndms, inBin, dm_low, dm_high, dm_step, tsamp_original, enable_fdas_custom_fft, enable_fdas_inbin, enable_fdas_norm, sigma_constant, enable_output_ffdot_plan, enable_output_fdas_list);
		//
		timer.Stop();
		float time = timer.Elapsed()/1000;
		printf("\n\n === OVERALL TDAS THROUGHPUT INCLUDING SYNCS AND DATA TRANSFERS ===\n");

		printf("\nPerformed Acceleration Location: %lf (GPU estimate)", time);
		printf("\nAmount of telescope time processed: %f", tstart_local);
		printf("\nNumber of samples processed: %ld", inc);
		printf("\nReal-time speedup factor: %lf", ( tstart_local ) / ( time ));
	}
}
