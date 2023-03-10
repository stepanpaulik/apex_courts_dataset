# Attach Packages
xfun::pkg_attach2("tidyverse", "kernlab", "e1071", "ISLR", "RColorBrewer", "word2vec", "rapportools", "foreach", "progress", "doParallel", "word2vec")

# Load data
load("data/US_texts.RData")
load("data/US_metadata.RData")
load("data/US_texts_paragraphs.RData")
load("data/US_dissents.RData")

# Load UDModel
# load("models/US_UDmodel.RData")

# Create paragraphs
data_paragraphs <- data_ud %>% group_by(doc_id, paragraph_id) %>% summarise(paragraph = paste0(token, collapse = " "))

# Create sample for manual tagging
sample <- data_metadata %>% 
  filter(is.empty(dissenting_opinion)) %>% 
  slice_sample(n = 50)
sample_paragraphs <- data_metadata %>% 
  filter(!is.empty(dissenting_opinion)) %>% 
  slice_sample(n = 50) %>% 
  rbind(., sample) %>% 
  select(doc_id) %>% 
  left_join(sample, ., by = "doc_id")


# Split the texts into paragraphs and index them
paragraphs_split <- function(data_texts) {
  
  # Create temporary object with doc_id + text split up into paragraphs
  data_paragraphs_temp <- data_texts %>% select(doc_id)
  data_paragraphs_temp$paragraphs <- foreach(i = seq(data_texts$doc_id), .combine='c') %do% {
    data_texts$text[i] %>% str_split(., pattern = "\n\n")
  }
  
  # Set up progress_bar
  pb <- progress_bar$new(
    format = "  extracting paragraphs [:bar] :percent eta: :eta",
    total = length(data_paragraphs_temp), clear = FALSE, width= 60)
  
  # The meat of the function: nested foreach loop
  data_paragraphs <- foreach(i = seq(data_paragraphs_temp$doc_id), .combine='rbind') %:%
    foreach(j = 1:length(data_paragraphs_temp$paragraphs[[i]]), .combine = 'rbind') %do%
    {
      paragraph_temp <- data_paragraphs_temp$paragraphs[[i]][j] %>% str_trim(side = "both")
      location_temp <- str_locate(string = data_texts$text[data_texts$doc_id == data_paragraphs_temp$doc_id[i]], pattern = fixed(data_paragraphs_temp$paragraphs[[i]][j])) %>% as.list()
      text_length <- str_length(data_texts$text[data_texts$doc_id == data_paragraphs_temp$doc_id[i]])
      
      list(
        "doc_id" = data_paragraphs_temp$doc_id[i], 
        "paragraph_id" = j, 
        "paragraph_text" = paragraph_temp, 
        "paragraph_start" = as.numeric(location_temp[1])/text_length, 
        "paragraph_end" = as.numeric(location_temp[2])/text_length, 
        "paragraph_length" = str_length(paragraph_temp)/text_length
      )
      pb$tick()
    } %>% as.data.frame(row.names = FALSE)
  return(data_paragraphs)
}

# Run the function and save the file
data_paragraphs <- paragraphs_split(data_texts = data_texts)
save(data_paragraphs, file = "data/US_texts_paragraphs.RData")

# Embeddings
parts_embeddings <- doc2vec(texts_embeddings, decisions_annotated)

# Paralelization
  n.cores <- parallel::detectCores() - 3
  my.cluster <- parallel::makeCluster(
    n.cores, 
    type = "PSOCK"
  )
  
#register it to be used by %dopar%
doParallel::registerDoParallel(cl = my.cluster)

#check if it is registered (optional)
foreach::getDoParRegistered()
foreach::getDoParWorkers()
  
# Paralelized function
  paragraphs_split_par <- function(data_texts) {
    
    data_paragraphs_temp <- data_texts %>% select(doc_id)
    pb <- progress_bar$new(
      format = "  extracting paragraphs [:bar] :percent eta: :eta",
      total = length(data_paragraphs_temp$doc_id), clear = FALSE, width= 60)
    
    data_paragraphs_temp$paragraphs <- foreach(i = seq(data_texts$doc_id), .combine='c') %do% {
      data_texts$text[i] %>% str_split(., pattern = "\n\n")
      pb$tick()
    }
    
    print("Texts have been split up into paragraphs")
    
    data_paragraphs <- foreach(i = seq(data_paragraphs_temp$doc_id), .combine='rbind', .packages=c("tidyverse", "foreach", "doParallel")) %:%
      foreach(j = 1:length(data_paragraphs_temp$paragraphs[[i]]), .combine = 'rbind') %dopar%
      {
        paragraph_temp <- data_paragraphs_temp$paragraphs[[i]][j] %>% str_trim(side = "both")
        location_temp <- str_locate(string = data_texts$text[data_texts$doc_id == data_paragraphs_temp$doc_id[i]], pattern = fixed(data_paragraphs_temp$paragraphs[[i]][j])) %>% as.list()
        text_length <- str_length(data_texts$text[data_texts$doc_id == data_paragraphs_temp$doc_id[i]])
        
        list(
          "doc_id" = data_paragraphs_temp$doc_id[i], 
          "paragraph_id" = j, 
          "paragraph_text" = paragraph_temp, 
          "paragraph_start" = as.numeric(location_temp[1])/text_length, 
          "paragraph_end" = as.numeric(location_temp[2])/text_length, 
          "paragraph_length" = str_length(paragraph_temp)/text_length
        )
      } %>% 
      as.data.frame(row.names = FALSE)
    return(data_paragraphs)
}
  
start_time <- Sys.time()
data_paragraphs_par <- paragraphs_split_par(data_texts = data_texts)
end_time <- Sys.time()

end_time - start_time
parallel::stopCluster(cl = my.cluster)

# Word2vec
# Window parameter:  for skip-gram usually around 10, for cbow around 5
# Sample: sub-sampling of frequent words: can improve both accuracy and 
# speed for large data sets (useful values are in range 0.001 to 0.00001)
# # hs: the training algorithm: hierarchical so????max (better for infrequent
# words) vs nega????ve sampling (better for frequent words, better with low
#                              dimensional vectors)
word2vec_model_CBOW <- word2vec(x = data_texts$text, dim = 300)
save(word2vec_model_CBOW, file = "models/word2vec_model_CBOW.RData")
load(file = "models/word2vec_model_CBOW.RData")

word2vec_model_skipgram <- word2vec(x = data_texts$text, dim = 300, type = "skip-gram", window = 10)
save(word2vec_model_skipgram, file = "models/word2vec_model_CBOW.RData")

embedding <- as.matrix(word2vec_model_CBOW)
embedding <- predict(word2vec_model_CBOW, c("soud", "st????ovatel"), type = "nearest")
embedding

# SVM

# SVM learning
# # Construct sample data set - completely separated
# x <- matrix(rnorm(20*2), ncol = 2)
# y <- c(rep(-1,10), rep(1,10))
# x[y==1,] <- x[y==1,] + 3/2
# dat <- data.frame(x=x, y=as.factor(y))
# 
# # Plot data
# ggplot(data = dat, aes(x = x.2, y = x.1, color = y, shape = y)) + 
#   geom_point(size = 2) +
#   scale_color_manual(values=c("#000000", "#FF0000")) +
#   theme(legend.position = "none")
# 
# # Fit Support Vector Machine model to data set with e1071
# svmfit <- svm(y~., data = dat, kernel = "linear", scale = FALSE)
# # Plot Results
# plot(svmfit, dat)
# 
# # fit model and produce plot with kernlab
# kernfit <- ksvm(x, y, data = dat, type = "C-svc", kernel = 'vanilladot')
# plot(kernfit, data = x)
# 
# # Construct sample data set - not completely separated
# x <- matrix(rnorm(20*2), ncol = 2)
# y <- c(rep(-1,10), rep(1,10))
# x[y==1,] <- x[y==1,] + 1
# dat <- data.frame(x=x, y=as.factor(y))
# 
# # Plot data set
# ggplot(data = dat, aes(x = x.2, y = x.1, color = y, shape = y)) + 
#   geom_point(size = 2) +
#   scale_color_manual(values=c("#000000", "#FF0000")) +
#   theme(legend.position = "none")
# 
# # Fit Support Vector Machine model to data set
# svmfit <- svm(y~., data = dat, kernel = "linear", cost = 100)
# # Plot Results
# plot(svmfit, dat)
# 
# # Fit Support Vector Machine model to data set
# kernfit <- ksvm(x,y, data = dat, type = "C-svc", kernel = 'vanilladot', C = 100)
# # Plot results
# plot(kernfit, data = x)
# 
# # find optimal cost of misclassification
# tune.out <- tune(svm, y~., data = dat, kernel = "linear",
#                  ranges = list(cost = c(0.001, 0.01, 0.1, 1, 5, 10, 100)))
# # extract the best model
# (bestmod <- tune.out$best.model)
# 
# # Create a table of misclassified observations
# ypred <- predict(bestmod, dat)
# (misclass <- table(predict = ypred, truth = dat$y))
# 
# # construct larger random data set
# x <- matrix(rnorm(200*2), ncol = 2)
# x[1:100,] <- x[1:100,] + 2.5
# x[101:150,] <- x[101:150,] - 2.5
# y <- c(rep(1,150), rep(2,50))
# dat <- data.frame(x=x,y=as.factor(y))
# 
# # Plot data
# ggplot(data = dat, aes(x = x.2, y = x.1, color = y, shape = y)) + 
#   geom_point(size = 2) +
#   scale_color_manual(values=c("#000000", "#FF0000")) +
#   theme(legend.position = "none")
# 
# # sample training data and fit model
# train <- base::sample(200,100, replace = FALSE)
# svmfit <- svm(y~., data = dat[train,], kernel = "radial", gamma = 1, cost = 10)
# # plot classifier
# plot(svmfit, dat)
# 
# # Fit radial-based SVM in kernlab
# kernfit <- ksvm(x[train,],y[train], type = "C-svc", kernel = 'rbfdot', C = 10, scaled = c())
# # Plot training data
# plot(kernfit, data = x[train,])
# 
# # find optimal cost of misclassification
# tune.out <- tune(svm, y~., data = dat[train,], kernel = "radial",
#                  ranges = list(cost = c(0.1,1,10,100,1000),
#                                gamma = c(0.5,1,2,3,4)))
# # extract the best model
# (bestmod <- tune.out$best.model)
# (valid <- table(true = dat[-train,"y"], pred = predict(tune.out$best.model,
#                                                        newx = dat[-train,])))
# 
# # Multiclass SVM
# x <- rbind(x, matrix(rnorm(50*2), ncol = 2))
# y <- c(y, rep(0,50))
# x[y==0,2] <- x[y==0,2] + 2.5
# dat <- data.frame(x=x, y=as.factor(y))
# # plot data set
# ggplot(data = dat, aes(x = x.2, y = x.1, color = y, shape = y)) + 
#   geom_point(size = 2) +
#   scale_color_manual(values=c("#000000","#FF0000","#00BA00")) +
#   theme(legend.position = "none")
# 
# # fit model
# svmfit <- svm(y~., data = dat, kernel = "radial", cost = 10, gamma = 1)
# # plot results
# plot(svmfit, dat)
# 
# 
# 
# # fit model
# dat <- data.frame(x = Khan$xtrain, y=as.factor(Khan$ytrain))
# (out <- svm(y~., data = dat, kernel = "linear", cost=10))
# 
# table(out$fitted, dat$y)
# 
# dat.te <- data.frame(x=Khan$xtest, y=as.factor(Khan$ytest))
# pred.te <- predict(out, newdata=dat.te)
# table(pred.te, dat.te$y)
# j