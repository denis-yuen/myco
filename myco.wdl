version 1.0

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.0.1/workflows/refprep-TB.wdl" as clockwork_ref_prepWF
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/combo_decontam/tasks/combined_decontamination.wdl" as clckwrk_combonation
#import "../clockwork-wdl/tasks/combined_decontamination.wdl" as clckwrk_combonation
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.0.1/tasks/variant_call_one_sample.wdl" as clckwrk_var_call
import "https://raw.githubusercontent.com/aofarrel/SRANWRP/main/tasks/pull_fastqs.wdl" as sranwrp_pull
import "https://raw.githubusercontent.com/aofarrel/SRANWRP/main/tasks/processing_tasks.wdl" as sranwrp_processing
import "https://raw.githubusercontent.com/aofarrel/parsevcf/main/vcf_to_diff.wdl" as diff

workflow myco {
	input {
		File biosample_accessions
		File typical_tb_masked_regions
		Int min_coverage
	}

	call clockwork_ref_prepWF.ClockworkRefPrepTB

	call sranwrp_processing.extract_accessions_from_file as get_sample_IDs {
		input:
			accessions_file = biosample_accessions
	}

	scatter(biosample_accession in get_sample_IDs.accessions) {
		call sranwrp_pull.pull_fq_from_biosample as pull {
			input:
				biosample_accession = biosample_accession
		} # output: pull.fastqs

		if(length(pull.fastqs)>1) {
    		Array[File] paired_fastqs=select_all(pull.fastqs)
  		}
	}

	
	Array[Array[File]] pulled_fastqs = select_all(paired_fastqs)

	scatter(pulled_fastq in pulled_fastqs) {
		call clckwrk_combonation.combined_decontamination_single as decontaminate_single_task {
			input:
				unsorted_sam = true,
				reads_files = pulled_fastq,
				tarball_ref_fasta_and_index = ClockworkRefPrepTB.tar_indexd_dcontm_ref,
				ref_fasta_filename = "ref.fa"
		}

		call clckwrk_var_call.variant_call_one_sample_verbose as varcall {
			input:
				sample_name = decontaminate_single_task.sample_name,
				ref_dir = ClockworkRefPrepTB.tar_indexd_H37Rv_ref,
				reads_files = [decontaminate_single_task.decontaminated_fastq_1, decontaminate_single_task.decontaminated_fastq_2]
		} # output: varcall.vcf_final_call_set, varcall.mapped_to_ref

	}

	Array[File] minos_vcfs=select_all(varcall.vcf_final_call_set)
	Array[File] bams_to_ref=select_all(varcall.mapped_to_ref)


	scatter(vcfs_and_bams in zip(bams_to_ref, minos_vcfs)) {
		call diff.make_mask_and_diff {
			input:
				bam = vcfs_and_bams.left,
				vcf = vcfs_and_bams.right,
				min_coverage = min_coverage,
				tbmf = typical_tb_masked_regions
		}
	}

	output {
		# outputting everything for debugging purposes
		Array[File] reads_mapped_to_decontam  = decontaminate_single_task.mapped_reads
		Array[File] reads_mapped_to_H37Rv = bams_to_ref
		Array[File] dcnfq1= decontaminate_single_task.decontaminated_fastq_1
		Array[File] dcnfq2= decontaminate_single_task.decontaminated_fastq_2
		Array[File] minos = minos_vcfs
		Array[File] masks = make_mask_and_diff.mask_file
		Array[File] diffs = make_mask_and_diff.diff
		Array[File?] debug_error_varcall = varcall.debug_error
	}
}