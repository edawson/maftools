createOncoMatrix = function(m, g = NULL, chatty = TRUE){

  if(is.null(g)){
    stop("Please provde atleast two genes!")
  }

  maf = subsetMaf(maf = m, genes = g, includeSyn = FALSE)

  oncomat = data.table::dcast(data = maf[,.(Hugo_Symbol, Variant_Classification, Tumor_Sample_Barcode)], formula = Hugo_Symbol ~ Tumor_Sample_Barcode,
                              fun.aggregate = function(x){
                                x = unique(as.character(x))
                                xad = x[x %in% c('Amp', 'Del')]
                                xvc = x[!x %in% c('Amp', 'Del')]

                                if(length(xvc)>0){
                                  xvc = ifelse(test = length(xvc) > 1, yes = 'Multi_Hit', no = xvc)
                                }

                                x = ifelse(test = length(xad) > 0, yes = paste(xad, xvc, sep = ';'), no = xvc)
                                x = gsub(pattern = ';$', replacement = '', x = x)
                                x = gsub(pattern = '^;', replacement = '', x = x)
                                return(x)
                              } , value.var = 'Variant_Classification', fill = '', drop = FALSE)

  #convert to matrix
  data.table::setDF(oncomat)
  rownames(oncomat) = oncomat$Hugo_Symbol
  oncomat = as.matrix(oncomat[,-1, drop = FALSE])

  variant.classes = as.character(unique(maf[,Variant_Classification]))
  variant.classes = c('',variant.classes, 'Multi_Hit')
  names(variant.classes) = 0:(length(variant.classes)-1)

  #Complex variant classes will be assigned a single integer.
  vc.onc = unique(unlist(apply(oncomat, 2, unique)))
  vc.onc = vc.onc[!vc.onc %in% names(variant.classes)]
  names(vc.onc) = rep(as.character(as.numeric(names(variant.classes)[length(variant.classes)])+1), length(vc.onc))
  variant.classes2 = c(variant.classes, vc.onc)

  oncomat.copy <- oncomat
  #Make a numeric coded matrix
  for(i in 1:length(variant.classes2)){
    oncomat[oncomat == variant.classes2[i]] = names(variant.classes2)[i]
  }

  #If maf has only one gene
  if(nrow(oncomat) == 1){
    mdf  = t(matrix(as.numeric(oncomat)))
    rownames(mdf) = rownames(oncomat)
    colnames(mdf) = colnames(oncomat)
    return(list(oncoMatrix = oncomat.copy, numericMatrix = mdf, vc = variant.classes))
  }

  #convert from character to numeric
  mdf = as.matrix(apply(oncomat, 2, function(x) as.numeric(as.character(x))))
  rownames(mdf) = rownames(oncomat.copy)


  #If MAF file contains a single sample, simple sorting is enuf.
  if(ncol(mdf) == 1){
    mdf = as.matrix(mdf[order(mdf, decreasing = TRUE),])
    colnames(mdf) = sampleId

    oncomat.copy = as.matrix(oncomat.copy[rownames(mdf),])
    colnames(oncomat.copy) = sampleId

    return(list(oncoMatrix = oncomat.copy, numericMatrix = mdf, vc = variant.classes))
  } else{
    #Sort by rows as well columns if >1 samples present in MAF
    #Add total variants per gene
    mdf = cbind(mdf, variants = apply(mdf, 1, function(x) {
      length(x[x != "0"])
    }))
    #Sort by total variants
    mdf = mdf[order(mdf[, ncol(mdf)], decreasing = TRUE), ]
    #colnames(mdf) = gsub(pattern = "^X", replacement = "", colnames(mdf))
    nMut = mdf[, ncol(mdf)]

    mdf = mdf[, -ncol(mdf)]

    mdf.temp.copy = mdf #temp copy of original unsorted numeric coded matrix

    mdf[mdf != 0] = 1 #replacing all non-zero integers with 1 improves sorting (& grouping)
    tmdf = t(mdf) #transposematrix
    mdf = t(tmdf[do.call(order, c(as.list(as.data.frame(tmdf)), decreasing = TRUE)), ]) #sort

    mdf.temp.copy = mdf.temp.copy[rownames(mdf),] #organise original matrix into sorted matrix
    mdf.temp.copy = mdf.temp.copy[,colnames(mdf)]
    mdf = mdf.temp.copy

    #organise original character matrix into sorted matrix
    oncomat.copy <- oncomat.copy[,colnames(mdf)]
    oncomat.copy <- oncomat.copy[rownames(mdf),]

    return(list(oncoMatrix = oncomat.copy, numericMatrix = mdf, vc = variant.classes))
  }
}

#---- This is small function to sort genes according to total samples in which it is mutated.
sortByMutation = function(numMat, maf){

  geneOrder = getGeneSummary(x = maf)[order(MutatedSamples, decreasing = TRUE), Hugo_Symbol]
  numMat = numMat[geneOrder[geneOrder %in% rownames(numMat)],, drop = FALSE]

  numMat[numMat != 0] = 1 #replacing all non-zero integers with 1 improves sorting (& grouping)
  tnumMat = t(numMat) #transposematrix
  numMat = t(tnumMat[do.call(order, c(as.list(as.data.frame(tnumMat)), decreasing = TRUE)), ]) #sort

  return(numMat)
}

#Thanks to Ryan Morin for the suggestion (https://github.com/rdmorin)
#original code has been changed with vectorized code, in-addition performs class-wise sorting.
sortByAnnotation <-function(numMat,maf, anno, annoOrder = NULL){
  anno.spl = split(anno, as.factor(as.character(anno[,1]))) #sorting only first annotation
  anno.spl.sort = sapply(X = anno.spl, function(x){
    numMat[,colnames(numMat)[colnames(numMat) %in% rownames(x)], drop = FALSE]
  })

  anno.spl.sort = anno.spl.sort[names(sort(unlist(lapply(anno.spl.sort, ncol)), decreasing = TRUE))] #sort list according to number of elemnts in each classification

  if(!is.null(annoOrder)){
    annoSplOrder = names(anno.spl.sort)

    if(length(annoOrder[annoOrder %in% annoSplOrder]) == 0){
      message("Values in provided annotation order ", paste(annoOrder, collapse = ", ")," does not match values in clinical features. Here are the available features..")
      print(annoSplOrder)
      stop()
    }
    annoOrder = annoOrder[annoOrder %in% annoSplOrder]

    anno.spl.sort = anno.spl.sort[annoOrder]

    if(length(annoSplOrder[!annoSplOrder %in% annoOrder]) > 0){
      warning("Following levels are missing from the provided annotation order: ", paste(annoSplOrder[!annoSplOrder %in% annoOrder], collapse = ", "))
    }
  }

  numMat.sorted = c()
  for(i in 1:length(anno.spl.sort)){
    numMat.sorted  = cbind(numMat.sorted, anno.spl.sort[[i]])
  }

  return(numMat.sorted)
}

#Sort columns while keeping gene order
sortByGeneOrder = function(m, g){
  m = m[g,, drop = FALSE]
  tsbs= colnames(m)
  tsb.anno = data.table::data.table()

  for(i in 1:nrow(m)){
    x = m[i,]
    tsb.anno = rbind(tsb.anno, data.table::data.table(tsbs = names(x[x!=0]), gene = g[i]))
  }
  tsb.anno = tsb.anno[!duplicated(tsbs)]

  if(length(tsbs[!tsbs %in% tsb.anno[,tsbs]]) > 0){
    tsb.anno = rbind(tsb.anno, data.table::data.table(tsbs = tsbs[!tsbs %in% tsb.anno[,tsbs]], gene = NA))
  }
  data.table::setDF(tsb.anno)
  #m.sorted = sortByAnnotation(numMat = m, anno = tsb.anno)

  anno.spl = split(tsb.anno, as.factor(as.character(tsb.anno$gene)))
  anno.spl.sort = sapply(X = anno.spl, function(x){
    m[,colnames(m)[colnames(m) %in% x$tsbs], drop = FALSE]
  })

  numMat.sorted = c()
  for(i in 1:length(anno.spl.sort)){
    numMat.sorted  = cbind(numMat.sorted, anno.spl.sort[[i]])
  }

  return(numMat.sorted)
}
