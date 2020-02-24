# Demonstration of Funk MF on images
# Core factorization transposed from python tutorial (written by Albert Au Yeung) into R. 
# Variable name adjustments made for programmers. Additional QOL adjustments made.
# All additional functionality (image handling, parallelism, ect) added by Ray Bosman

#Function to corrupt a matrix
corruptImage <- function(p_imageData,p_corruption) {
  print("Corrupting data...")
  for (i in 1:dim(p_imageData)[1]) {
    for (j in 1:dim(p_imageData)[2]) {
      if (runif(1,0,1) < (p_corruption)) {
      p_imageData[i,j] <- 0
      }
    }
  }
  return(p_imageData)
}

#Pass in a matrix, average outliers by surrounding pixels. Used for any blown out pixels.
MeanPixel <- function(pixelMatrix) {
  print("Smoothing outlier pixels...")
  for(i in 1:nrow(pixelMatrix)) { 
    for(j in 1:ncol(pixelMatrix)) {

      #Any outlying pixels beyond 1 or below 0 are smoothed out
      if (pixelMatrix[i,j] > 1 || pixelMatrix[i,j] < 0) {
	#Select 4 surrounding pixel coordinates
        pix1 <- c(i-1,j)
        pix2 <- c(i,j-1)
        pix3 <- c(i+1,j)
        pix4 <- c(i,j+1)
      
	#If the pixel is on a margin, move it within bounds
        pix1[1] <- ifelse(pix1[1]<1,1,pix1[1])
        pix2[2] <- ifelse(pix2[2]<1,1,pix2[2])
        pix3[1] <- ifelse(pix3[1]>nrow(pixelMatrix),nrow(pixelMatrix),pix3[1])
        pix4[2] <- ifelse(pix4[2]>ncol(pixelMatrix),ncol(pixelMatrix),pix4[2])
        
        #Set the value to the average
        pixelMatrix[i,j] <- mean(pixelMatrix[pix1[1],pix1[2]]
                                ,pixelMatrix[pix2[1],pix2[2]]
                                ,pixelMatrix[pix3[1],pix3[2]]
                                ,pixelMatrix[pix4[1],pix4[2]])
      
      }
    }
  }
  return(pixelMatrix)
}

#Factorization function : Original python code found at http://www.albertauyeung.com/post/python-matrix-factorization/
#Written in python by Albert Au Yeung. Transposed to R and some variable names changed.
#X refers to columns, Y refers to rows. X -> N&j, Y -> M&i. K refers to width of Y, or height of X
matrix_factorization <- function(R, K, steps, p_inita, p_initb, alpha, beta) {
  
  #Each function call receives an ID so it can be monitored in the cluster.txt file
  functionId <- sample(1:1000,1)  
  
  #Get matrix dimensions
  M <- nrow(R)
  N <- ncol(R)

  #Load X with uniform numbers
  X <- sample(seq(p_inita,p_initb, length = 100),N*K,replace = T)
  dim(X) <- c(K,N)
  X <- as.matrix(X)
  
  #Load Y with uniform numbers
  Y <- sample(seq(p_inita,p_initb, length = 100),M*K,replace = T)
  dim(Y) <- c(M,K)
  Y <- as.matrix(Y)

  #Steps (like epochs)
  for (x in 1:steps ) {

    #Iterated through M then N (rows then columns per row)
    for (i in 1:nrow(R)) {
      for (j in 1:ncol(R)) {
        #if the matrix element has a value, adjust the coefficients
        if ( R[i,j] > 0) {

          #Compute the synthetic pixel and the error 
          #(difference between real pixel and synthetic pixel)
          spixel <- Y[i,] %*% X[,j]
          eij <- (R[i,j] - spixel)

          #Adjust X and Y coefficients with pde of error
          for (k in 1:K) {
            Y[i,k] <- Y[i,k] - alpha * (-2 * (eij) * X[k,j] + beta * Y[i,k])
            X[k,j] <- X[k,j] - alpha * (-2 * (eij) * Y[i,k] + beta * X[k,j])
          }
        }
      }

      e <- 0
      
      #Aggregate the errors and then report
      for (i in 1:nrow(R)) {
        for (j in 1:ncol(R))  {
          if (R[i,j] > 0) {
            e <- e + (R[i,j]-Y[i,] %*% X[,j])^2
            }
        }
      }

      if (x %% 50 == 0) {
        print(paste("functionid:",functionId,"step:",x,",","err:",e))
      }

      if (!is.na(e)) {
        if(e< 0.001) {
          break
        }
      }
    }
  }
  #Return the synthetic matrix
  return (as.matrix(as.data.frame(Y)) %*% as.matrix(as.data.frame(X)))
}

#The main function, takes in all the parameters needed to restore a corrupted image. Descriptions in imageFactorization.R
CorrectImage <- function(p_image_directory,p_image,p_blockx,p_blocky,p_step,p_rate,p_factor,p_inita,p_initb,p_corruption,p_cpu) {
  
  print(paste("Init ",p_cpu," cpu/s..."))
  #Configure CPU cluster, write output to cluster.txt where the image resides
  cl <- makeCluster(p_cpu,outfile = paste0(p_image_directory,"cluster.txt"))
  
  print(paste("Loading data..."))
  #read image and use only first png dimension
  imageData <- readPNG(paste0(p_image_directory,p_image))
  imageData <- imageData[,,1]
  
  #Corrupt the image
  imageDataCorrupt <- corruptImage(imageData,p_corruption)

  print(paste("Plotting corrupted image..."))
  image(t(apply(imageDataCorrupt, 2, rev)),col=grey(seq(0, 1, length = 256)))
     
  #set to global loop to 1.
  #If its greater than 1, the image will be corrected by a few pixels at a time.
  #Results fed back into algorithm for g passes
  print(paste("Begin main loop..."))
  globalLoop <- 1
  for (g in 1:globalLoop) {
    #initialise values
    ArrayList <- list()
    imageSyntheticCombined <- NULL
    mCount <- 0
	
    #If we're doing our first pass, intialise imageMatrix
    if (g==1) {
      imageMatrix <- as.matrix(imageDataCorrupt)
    }
    else {
      imageMatrix <- imageSyntheticCombined
    }

    #Get the number of blocks to be looped over
    msize <- dim(t(imageDataCorrupt))[2]/(p_blocky)
    nsize <- dim(t(imageDataCorrupt))[1]/(p_blockx)
    
    #Get the image size (t is for transpose, the image is on its side in matrix form)
    m <- dim(t(imageDataCorrupt))[2]
    n <- dim(t(imageDataCorrupt))[1]
    
    #If we're dividing our image into sub matrices - proceed to cut image up for processing
    if (msize > 1) {
      print(paste("..Dividing image..."))  
      for (m in 1:msize) {
        for (n in 1:nsize) {
          mCount <- mCount+1
          lowerLimitm <- (m*p_blocky)-(p_blocky-1)
          lowerLimitn <- (n*p_blockx)-(p_blockx-1)
          upperLimitm <- (m*p_blocky)
          upperLimitn <- (n*p_blockx)
          ArrayList[[mCount]] <- imageMatrix[lowerLimitm:upperLimitm,lowerLimitn:upperLimitn]
        }
      }
    }
    else {
      ArrayList[[1]] <- imageMatrix[1:dim(imageDataCorrupt)[2],1:dim(imageDataCorrupt)[1]]
    }
  
    #Farm out sub matrices from image to each CPU core in p_cpu
    print("....Sending off workload to CPUs, tail -f -n 100 cluster.txt")
    print("....in your image directory to monitor. No feedback in R...")
    imageSyntheticList <- parSapply(cl=cl,ArrayList,p_factor,p_step,p_inita,p_initb,p_rate,.001,FUN = matrix_factorization, simplify=F)

    print("..Threading the matrices back together again. Minor adjustments if outlier pixels found...")
    for (x in 1:length(imageSyntheticList)) {
      #if the pixel has a nan, replace with surrounding pixels
      if ( is.nan(max(imageSyntheticList[[x]])) == T) {
        imageSyntheticList[[x]] <- MeanPixel(imageSyntheticList[[x]])
        imageSyntheticList[[x]] <- ifelse(imageSyntheticList[[x]]>1,.96,imageSyntheticList[[x]])
      }

      #if the pixel has value > 1 (bright), smooth with mean
      if (max(imageSyntheticList[[x]]) >= 1) {
        imageSyntheticList[[x]] <- MeanPixel(imageSyntheticList[[x]])
        imageSyntheticList[[x]] <- ifelse(imageSyntheticList[[x]]>1,.96,imageSyntheticList[[x]])
      }

      #if the pixel has value < 0 (dark), smooth with mean
      if (min(imageSyntheticList[[x]]) <= 0) {
        imageSyntheticList[[x]] <- MeanPixel(imageSyntheticList[[x]])
        imageSyntheticList[[x]] <- ifelse(imageSyntheticList[[x]]<0,.01,imageSyntheticList[[x]])
      }

    }

    #Start to merge the synthetic arrays back together after processing
    #merge by columns and by row
    mCount <- 1
    for (m in 1:msize) {
      imageSynthetic <- NULL
      #First load matrices horizontally
      for (n in 1:nsize) {
        if (is.null(imageSynthetic)) {
          imageSynthetic <- imageSyntheticList[[mCount]]
        }
        else {
          imageSynthetic <- cbind(imageSynthetic,imageSyntheticList[[mCount]])   
        }
        mCount <- mCount+1
      }

      #Then we append the horizontally bound matrices onto a row
      if (is.null(imageSyntheticCombined)) {
        imageSyntheticCombined <- imageSynthetic
      }
      else {
        imageSyntheticCombined <- rbind(imageSyntheticCombined,imageSynthetic)   
      }
    }
  
    print("..start imputing pixels back into our corrupted image...")
    #Imput every 3rd pixel unless global processing is set to 1
    samplecount <- 0
    imageDataCorrected <- imageMatrix
    for (i in 1:nrow(imageDataCorrected)) {
      for (j in 1:ncol(imageDataCorrected)) {
        if(imageDataCorrected[i,j] == 0) {
          if (samplecount >= 3 || g==globalLoop) {
            imageDataCorrected[i,j] <-  imageSyntheticCombined[i,j]
            samplecount <- 0
          }
          samplecount <- samplecount+1
        }
      }
    }
  
    #Render an image plot of the 3 images, Corrupted, Synthetic, Imputed
    par(mar=c(1,1,1,1))
    par(mfrow=c(1,3))
    
    print("..plot images for comparison...")
    image(t(apply(imageDataCorrupt, 2, rev)),col=grey(seq(0, 1, length = 256)))
    image(t(apply(imageSyntheticCombined, 2, rev)),col=grey(seq(0, 1, length = 256)))
    image(t(apply(imageDataCorrected, 2, rev)),col=grey(seq(0, 1, length = 256)))

    print("..write each image to disk at original resolution...")
    par(mfrow=c(1,1))

    #Corrupted
    png(filename=paste0(setting_image_directory,p_image,"",g,"_",p_image,"_",p_blocky,"_",p_rate,"_",p_step,"_",p_factor,"_corrupt.png"),width=dim(imageDataCorrupt)[2]+70*2,height=dim(imageDataCorrupt)[1]+70*2,units="px")
    image(t(apply(imageDataCorrupt, 2, rev)),col=grey(seq(min(imageDataCorrupt), max(imageDataCorrupt), length = 256)))
    dev.off()

    #Synthetic
    png(filename=paste0(setting_image_directory,p_image,"",g,"_",p_image,"_",p_blocky,"_",p_rate,"_",p_step,"_",p_factor,"_fact.png"),width=dim(imageDataCorrupt)[2]+70*2,height=dim(imageDataCorrupt)[1]+70*2,units="px")
    image(t(apply(imageSyntheticCombined, 2, rev)),col=grey(seq(min(imageSyntheticCombined), max(imageSyntheticCombined), length = 256)))
    dev.off()

    #Imputed
    png(filename=paste0(setting_image_directory,p_image,"",g,"_",p_image,"_",p_blocky,"_",p_rate,"_",p_step,"_",p_factor,"_corrected.png"),width=dim(imageDataCorrupt)[2]+70*2,height=dim(imageDataCorrupt)[1]+70*2,units="px")
    image(t(apply(imageDataCorrected, 2, rev)),col=grey(seq(min(imageDataCorrected), max(imageDataCorrected), length = 256)))
    dev.off()
  }

  print("stop the cluster...")
  stopCluster(cl)
  print("done.")
  return (0)
}
