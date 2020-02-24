# FactorizationMachine
**Image corruption correction using FunkMF**

Factorization machines are an approach to infer missing data using a loss function (with gradient descent) across the product of 2 different matrices. It is an approach popularized by Simon Funk in 2006 owing to his efforts on the Netflix recommendation prize. The aim of Funk MF is to minimize the error between a synthetic matrix, derived from 2 matrices, and the real data. This is done through the initialized coefficients stored in 2 matrices. Practical uses include restoring image corruption and generating recommendations or suggestions to users based on x and y pairs.

This particular project is an implementation of the same algorithm but in R with a focus on image restoration.
Special thanks to Albert Au Yeung, a very smart computer scienctist and machine learning engineer, for writing a tutorial on matrix factorization years ago. The tutorial involved the imputation of a MxN matrix and in python. I had a look at his tutorial after reading the math in trying to understand how Funk MF worked and found his work. Here, I began to transpose the code into R. 

**Execution**
Copy the files into a folder, set the parameters of imageFactorization.R to what you require along with the image folder name.
Parameters BLOCKX and BLOCKY determine the x and y dimensions of the size of the blocks you divide your image into.
Therefore, choose values that where your x and y image dimensions are divided, there are no remainders - factors of x and y.
Example, 100x100 image can be divided by 5,10,20,50,100 for x or y. The x and y of the blocks do not need to be the same.
The smaller the blocks, the more sub matrices that can be farmed off to your cpus to process in parallel.
Smaller blocks lead to faster performance but image results degrade in a non linear manner at a very small size.

K is another parameter that impacts performance as this determines the width and high of matrices X and Y (P and Q)
The higher the count, the finer the detail that can be captured from the image.

Execute the script and you should seen an output similar to that of below:

[1] "Init  10  cpu/s..."

[1] "Loading data..."

[1] "Corrupting data..."

[1] "Plotting corrupted image..."

[1] "Begin main loop..."

[1] "..Dividing image..."

[1] "....Sending off workload to CPUs, tail -f -n 100 cluster.txt"

[1] "....in your image directory to monitor. No feedback in R..."

[1] "Smoothing outlier pixels..."

[1] "Smoothing outlier pixels..."

.........................

[1] "Smoothing outlier pixels..."

[1] "Smoothing outlier pixels..."

[1] "..start imputing pixels back into our corrupted image..."

[1] "..Plot images for comparison..."

[1] "..Write each image to disk at original resolution..."

[1] "Stop the cluster..."

[1] "Done."

[1] 0

After successfully processing the following image

![Original](https://github.com/RayBosman/FactorizationMachine/blob/master/14.png)

You should see an output of the following images
**Corrupted**

![Corrupted](https://github.com/RayBosman/FactorizationMachine/blob/master/14.png1_14.png_37_0.02_400_20_corrupt.png)

**Synthetic**

![Synthetic](https://github.com/RayBosman/FactorizationMachine/blob/master/14.png1_14.png_37_0.02_400_20_fact.png)

**Corrected**

![Corrected](https://github.com/RayBosman/FactorizationMachine/blob/master/14.png1_14.png_37_0.02_400_20_corrected.png)
