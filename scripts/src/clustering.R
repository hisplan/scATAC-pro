source_local <- function(fname){
  argv <- commandArgs(trailingOnly = FALSE)
  base_dir <- dirname(substring(argv[grep("--file=", argv)], 8))
  source(paste(base_dir, fname, sep="/"))
}

source_local('dsAnalysis_utilities.R')

library(ggplot2)
library(parallel)
args = commandArgs(T)
mtx_file = args[1]
cluster_method = args[2]
k = args[3]
output_dir = args[4]
genome_name = args[5]
tss_path = args[6]
norm_by = args[7]

#library(reticulate)
#use_python(paste0(python_path, '/python'))

mtx = read_mtx_scATACpro(mtx_file)

tss_ann <- fread(tss_path, header = F)
names(tss_ann)[c(1:4,7)] <- c('chr', 'start', 'end', 'gene_name', 'gene_type')
tss_ann <- tss_ann[gene_type %in% c('miRNA', 'lincRNA', 'protein_coding'), ]

mtx = assignGene2Peak(mtx, tss_ann)

seurat.obj = doBasicSeurat_new(mtx, npc = 30, norm_by = norm_by, 
                               top.variable = 0.1, reg.var = 'nCount_ATAC')
if(cluster_method != 'cisTopic'){

    seurat.obj = RunTSNE(seurat.obj, dims = 1:30, reduction = 'pca', check_duplicates = FALSE)
    seurat.obj = RunUMAP(seurat.obj, dims = 1:30, reduction = 'pca', verbose = F)
}

saveRDS(seurat.obj, file = paste0(output_dir, '/seurat_obj.rds'))




## clustering
if(cluster_method == 'seurat'){
  ## seurat implemented louvain algorithm
  seurat.obj = FindNeighbors(seurat.obj, reduction = 'pca', dims = 1:30, k.param = 20)
  if (toupper(k) == 'NULL' || k == '0'){
    resl = 0.2
  }else{
   k = as.integer(k)
    resl = queryResolution4Seurat(seurat.obj, reduction = 'pca', npc = 30, k = k,
                                min_resl = 0.01)
  }
  seurat.obj = FindClusters(seurat.obj, resolution = resl)
  #seurat.obj$seurat_clusters = seurat.obj@active.ident
  seurat.obj$active_clusters = seurat.obj$seurat_clusters
}

if(cluster_method == 'cisTopic'){
  nc = detectCores()
  cis.obj = run_cisTopic(mtx, nCores = min(10, nc))
  sele.cisTopic <- selectModel(cis.obj, 
                               keepBinaryMatrix = F, keepModels = F)
  cell_topic <- t(modelMatSelection(sele.cisTopic, 'cell', 'Probability'))
  seurat.obj$cisTopic_clusters = generalCluster(cell_topic, method = 'hclust', k = k)
  seurat.obj$active_clusters = seurat.obj$cisTopic_clusters
  seurat.obj[['lda']] <- CreateDimReducObject(embeddings = cell_topic, 
                                              key = 'Topic', assay = DefaultAssay(seurat.obj))
    seurat.obj = RunTSNE(seurat.obj, dims = 1:ncol(cell_topic), reduction = 'lda', check_duplicates = FALSE)
    seurat.obj = RunUMAP(seurat.obj, dims = 1:ncol(cell_topic), reduction = 'lda', verbose = F)
  #saveRDS(cell_topic, file = paste0(output_dir, '/cell_topic_obj.rds'))
}

if(cluster_method == 'LSA'){
  seurat.obj$LSA_clusters = run_LSI(mtx, k = k)
  seurat.obj$active_clusters = seurat.obj$LSI_clusters
}


if(cluster_method == 'scABC'){
  seurat.obj$scABC_clusters = run_scABC(mtx, k = k)
  seurat.obj$active_clusters = seurat.obj$scABC_clusters
}

if(cluster_method == 'chromVar'){
  genomeName = 'BSgenome.Hsapiens.UCSC.hg38'
  if(grepl(genome_name, pattern = '38'))genomeName = 'BSgenome.Hsapiens.UCSC.hg38'
  if(grepl(genome_name, pattern = '19'))genomeName = 'BSgenome.Hsapiens.UCSC.hg19'
  if(grepl(genome_name, pattern = 'mm9'))genomeName = 'BSgenome.Mmusculus.UCSC.mm9'
  if(grepl(genome_name, pattern = 'mm10'))genomeName = 'BSgenome.Mmusculus.UCSC.mm10'
  nc = detectCores()
  obj = run_chromVAR(mtx, genomeName, max(1, nc - 1))
  saveRDS(obj, file = paste0(output_dir, '/chromVar_obj.rds'))
  pca_coords = doDimReduction4mat(obj@assays$data$z)[[1]]
  
  seurat.obj$chromVar_clusters = cutree(hclust(dist(pca_coords)), k = k)
  seurat.obj$active_clusters = as.factor(seurat.obj$chromVar_clusters)
  
  
}

saveRDS(seurat.obj, file = paste0(output_dir, '/seurat_obj.rds'))

#output bacrcode cluster information
bc_cls = data.table('Barcode' = rownames(seurat.obj@meta.data), 'Cluster' = seurat.obj@meta.data$active_clusters)
setkey(bc_cls, Cluster)

write.table(bc_cls, file = paste0(output_dir, '/cell_cluster_table.txt'), sep = '\t',
            quote = F, row.names = F)

cg <- DimPlot(seurat.obj, reduction = 'umap', group.by = 'active_clusters', label = T) + theme(legend.text = element_text(size = 17))
    
   pfname = paste0(output_dir, '/umap_clusters.eps')
   ggsave(cg, file = pfname, device = 'eps', width = 6, height = 6)

