#!/bin/bash


seuratObj_file=$1  ## seurat obj after clustering
 
# reading configure file
curr_dir=`dirname $0`
source ${curr_dir}/read_conf.sh
read_conf "$2"
read_conf "$3"

output_dir=${OUTPUT_DIR}/downstream_analysis/${CELL_CALLER}
mkdir -p $output_dir

curr_dir=`dirname $0`

${R_PATH}/Rscript --vanilla ${curr_dir}/src/runDA.R $seuratObj_file $output_dir $group1 $group2 $test_use

echo "Differential analysis done!"
