#!/bin/bash

input_bam=$1

# reading configure file
curr_dir=`dirname $0`
source ${curr_dir}/read_conf.sh
read_conf $2
read_conf $3


## 1.first bin genome
mtx_dir=${OUTPUT_DIR}/raw_matrix
echo "Getting bin by barcode matrix ..."
mtx_bin_dir=${mtx_dir}/${PEAK_CALLER}
mkdir -p $mtx_bin_dir
bin_file=${mtx_bin_dir}/${OUTPUT_PREFIX}_bin.bed
${BEDTOOLS_PATH}/bedtools makewindows -g $CHROM_SIZE_FILE -w $BIN_RESL > $bin_file
${R_PATH}/R --vanilla --args ${OUTPUT_DIR}/summary/${OUTPUT_PREFIX}.fragments.txt $bin_file ${mtx_bin_dir} 2000 50 < ${curr_dir}/src/get_mtx.R
rm $bin_file


## 2.roughly clustering

output_dir=${OUTPUT_DIR}/peaks/${PEAK_CALLER}
mkdir -p $output_dir

${R_PATH}/Rscript --vanilla ${curr_dir}/src/clustering.R ${mtx_bin_dir}/matrix.mtx seurat 0 $output_dir $GENOME_NAME $TSS $norm_by


## remove cluster with less than 100 cells

${R_PATH}/Rscript --vanilla ${curr_dir}/src/rm_minor_cluster.R ${output_dir}/cell_cluster_table.txt 100

## 3.call peaks per cluster by macs2
## split bam into cluster
${PERL_PATH}/perl ${curr_dir}/src/split_bam2clusters.pl --cluster_file ${output_dir}/filtered_cell_cluster_table.txt --bam_file $input_bam \
    --output_dir $output_dir --samtools_path $SAMTOOLS_PATH


organism=hs
if [[ $GENOME_NAME =~ "mm" ]]; then
    organism=mm
fi

## call peaks per cluster
unset PYTHONHOME
unset PYTHONPATH
for input_bam0 in $(find $output_dir -name *.bam); do
    pre=$(basename $input_bam0)
    pre=${pre/.bam/}
    ${MACS2_PATH}/macs2 callpeak -t $input_bam0 --outdir $output_dir -n $pre -f BAM -g $organism $MACS2_OPTS &
done
wait



## 4. merge peaks
${R_PATH}/R --vanilla --args $output_dir < ${curr_dir}/src/merge_peaks.R

## remove peaks overlapped with blacklist
${BEDTOOLS_PATH}/bedtools intersect -a ${output_dir}/merged_peaks.bed -b $BLACKLIST -v \
    > ${output_dir}/${OUTPUT_PREFIX}_features_BlacklistRemoved.bed   

## remove intemediate files
rm ${output_dir}/cluster*

