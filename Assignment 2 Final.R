#test

####Install & Load Packages----

#install.packages("rentrez")
library(rentrez)
#install.packages("seqinr")
library(seqinr)
#BiocManager::install("Biostrings")
library(Biostrings)
#install.packages("tidyverse")
library(tidyverse)
#load randomforest
library(randomForest)



####Obtain MetaData with entrez_search()----

#Verify database's search terms
entrez_db_searchable("nuccore")

#Database choice: The sequences data will be obtained from the National Center for Biotechnology Information's (NCBI) RefSeq records, which provides a curated, non-redundant collection of high-quality sequences (Pruitt et al., 2007). This source was chosen to help facilitate data filtering and quality control, and reduce some sources of error (e.g. database sequence errors, misclassifications, low quality sequences, and the inclusion of regions outside of the 16S rRNA gene region). 


#Search NCBI's Nucleotide database for 16S rRNA Refseq records for Actinobacteria. This was then repeated for Firmicutes. Limited to 4000 hits for each taxa to prevent either taxa from being overrepresented in the model. Web history objects were used to support the high number of hits in entrez_fetch(). 
actino_search<-entrez_search(db = "nuccore", term = "(Actinobacteria[ORGN] AND (33175[BioProject] OR 33317[BioProject])", retmax = 4000,  use_history=TRUE)

#Search NCBI's Nucleotide database for 16S rRNA Refseq records for Firmicutes.  
firmi_search<-entrez_search(db = "nuccore", term = "(Firmicutes[ORGN] AND (33175[BioProject] OR 33317[BioProject])", retmax = 4000,  use_history=TRUE)



####Fetch Sequence Data using entrez_fetch()----

#Fetch Sequence data in FASTA format for respective taxa. Retmax specified since web-history object is being used. 
actino_fetch <- entrez_fetch(db = "nuccore", web_history=actino_search$web_history, rettype = "fasta", retmax=4000)
firmi_fetch <- entrez_fetch(db = "nuccore", web_history=firmi_search$web_history, rettype = "fasta", retmax=4000)

#Write sequence data to directory. FASTA files subsequently viewed with text editor. The following lines have been commented to prevent overwriting.
#write(actino_fetch, "actino_fetch.fasta", sep = "\n")
#write(firmi_fetch, "firmi_fetch.fasta", sep = "\n")



####Put Sequence Data into Dataframe----

#Read in FASTA files as DNA StringSets and verify class
actino_stringSet <- readDNAStringSet("actino_fetch.fasta")
firmi_stringSet <- readDNAStringSet("firmi_fetch.fasta")
class(actino_stringSet)
class(firmi_stringSet)

#Put sequences into dataframes (one dataframe per phylum)
dfactino <- data.frame(Title_16S = names(actino_stringSet), Sequence_16S = paste(actino_stringSet))
dffirmi <- data.frame(Title_16S = names(firmi_stringSet), Sequence_16S = paste(firmi_stringSet))

#Add a Phylum column to each dataframe
dfactinophylum<-dfactino %>% 
  add_column(Phylum="actinobacteria")
dffirmiphylum<-dffirmi %>% 
  add_column(Phylum="firmicutes")

##Combine the two dataframes into 1 dataframe
df_firmi_actino <-bind_rows(dffirmiphylum,dfactinophylum)



####Explore the Data----

#Check the class of the dataframe
class(df_firmi_actino)

#Check sequences for NAs (sum should be zero if no NAs present).
sum(is.na(df_firmi_actino$Sequence_16S))
sum(is.na(df_firmi_actino$Title_16S))

#Find maximum and minimum sequence lengths: 459-1774
summary(nchar(df_firmi_actino$Sequence_16S))

##Investigate Ns in the sequences
#Are there many Ns present in the sequences of the dataset as a whole? 10,436
sum(str_count(string = df_firmi_actino$Sequence_16S, pattern = "N"))
#Summary showing distribution of the Ns over the sequences in the dataset?
summary(str_count(string = df_firmi_actino$Sequence_16S, pattern = "N"))
#Histogram indicates the vast majority of sequences have a low number of Ns present (particularly relative to sequence length). This is accepted for the current analysis.
hist(str_count(string = df_firmi_actino$Sequence_16S, pattern = "N"), main="Histogram of N Frequency in 16S rRNA Gene Sequences from Actinobacteria or Firmicutes",xlab="Number of Ns")

#Verify that the Phylum column contains only the expected values.
unique(df_firmi_actino$Phylum)

#Check the range of the categorical features.
summary(df_firmi_actino)



####Calculate K-mers----


#Convert the sequences to DNAStringSet (actually- created a new column just to be safe)
df_firmi_actino$Sequence_16S2<-DNAStringSet(df_firmi_actino$Sequence_16S)

#Duplicate the dataframe for later (when we look at 2-mer and 3-mer calculations). Set aside
df_firmi_actino_k3 <-df_firmi_actino
df_firmi_actino_k2 <-df_firmi_actino

#Calculate K-mers of length 4 and append to dataframe 
df_firmi_actino <- cbind(df_firmi_actino, as.data.frame(oligonucleotideFrequency(df_firmi_actino$Sequence_16S2, 4)))



####Random Forest for 4-mers----


###Create a validation data set

#Convert Sequence_16S2 from a DNAStringSet back to a character data so tidyverse functions can be used 
df_firmi_actino$Sequence_16S2<-as.character(df_firmi_actino$Sequence_16S2)

#Set seed so results are reproducible in the future
set.seed(217)

#Sample 1000 individuals from each phylum (~25% of individuals per phylum)
dfvalidation<-df_firmi_actino %>% 
  group_by(Phylum)%>% 
  sample_n(1000)

#Confirm that phyla are equally represented in the validation set
dfvalidation %>% 
  group_by(Phylum) %>% 
  summarize(count=n())


###Create a Training Dataset

#Set seed so results are reproducible
set.seed(13)

#Create a training set composed of 2000 hits from each phylum
dfTraining <- df_firmi_actino%>%
  filter(!Title_16S %in% dfvalidation$Title_16S) %>% 
  group_by(Phylum) %>%
  sample_n(2000)

#Confirm that Phyla are equally represented in the training set
dfTraining %>% 
  group_by(Phylum) %>% 
  summarize(count=n())


###Build an RF Classifier

#Build a classifier to classify phylum by 4-mer frequency and assess the importance of predictors
phylum_classifier <- randomForest(x = dfTraining[, 5:260], y = as.factor(dfTraining$Phylum), ntree = 8000, importance = TRUE)

#Explanations for the most relevant model choices:
#n-tree set to be twice the size of the number of data points in the training set (4000) to enable so data points to make it into the model more than once; a higher ntree is not initially selected due to the greater computational power required, but it is understood that this can be revisited if model performance need to be improved.
#x=dfTraining[,5:260] because we're using the columns containing k-mer data as features to train our model
#y=as.factor because response vector is phylum (classifier)
#na.action omitted because there are no NAs in dataset
#xtest and ytest left to NULL, because we've already subsetted the data into training and test sets
#ntree=4000 because training set is 2000 observations and we want to ensure every input row gets predicted at least a few times
#mtry=sqrt(number of variables in x), the default for classification, was used. This is the number of variables randomly sampled as candidates at each split;found to negligibly impact classification rates (Cutler et al. 2007)
#replace=TRUE, the default, to sample with replacement because the predictive categories are relatively balanced and therefore we're less concerned about bias resulting from sampling with replacement
#classwt=NUll, the default, because data is balanced (4000 for each taxa)
#cutoff=1/k, the default probability  cutoff



###Assess the Results of the RF Classifier

#View an overview of the classifier: 0.18% OOB error estimate
phylum_classifier


##RF Validation Set Assessment #1: Confusion Matrix. Use random forest classifier to try and predict phylum for validation set

#Install and load  caret package need to create prediction
#install.packages("caret")
library(caret)

#Encode phylum (the target categorical feature) of validation data as factor with two levels. This is necessary because confusionMatrix() requires that 'data' and 'reference be factors with the same levels.
dfvalidation$Phylum = factor(dfvalidation$Phylum, levels = c("actinobacteria","firmicutes"))

#Create a prediction (of phylum, from test data) (using caret library)
phylum_prediction<-predict(phylum_classifier, newdata=dfvalidation[,5:260])

#Use the predication to create a confusion matrix and obtain an accuracy score.
confusion_matrix<-confusionMatrix(phylum_prediction,dfvalidation$Phylum)

#Print the confusion matrix; accuracy of 99.85%
print(confusion_matrix)


###Explore the Important Features in Random Forest Classifier

#Explore the classifier's importance, and assign to variable for later viewing
importance<-phylum_classifier$importance

#Plot the importance of each feature
varImpPlot(x=phylum_classifier, main="Feature Importance of Random Forest Phylum Classifier",col="black",bg="purple")

#Create a dataframe from importance() output
df_importance <- importance(phylum_classifier) %>% 
  data.frame() %>% 
  mutate(feature = row.names(.))

#Explore the column MeanDecreaseGini
summary(df_importance$MeanDecreaseGini)

#Create a boxplot of distribution of feature importance on log scale. Log axis was used because variability in importance is small relative to its range, and the boxplot was otherwise very 'squished'. Note the outliers with particularly high importance.
boxplot(df_importance$MeanDecreaseGini,
        xlab="Importance", ylab="Features", main="Boxplot Showing Distribution of 4-mer Feature Importance on Log Scale \nin Random Forest Classification of Actinobacteria or Firmicutes",log="x",horizontal=TRUE, col="lightgray",cex.lab=1.2)

#Create a dataframe containg a subset of the features (those with MeanDecreaseGini>50))
df_importance_50 <-df_importance %>% 
  filter(MeanDecreaseGini>50)

##Plot the above dataframe to view the features with the highest gini importance.
#Note:each feature's importance is assessed based on meandecreaseaccuracy (extent of loss in prediction performance when variable is omitted) and meandecreasegini (node impurity). 
ggplot(df_importance_50, aes(y = reorder(feature, MeanDecreaseGini),
                             x = MeanDecreaseGini)) +
  geom_bar(stat='identity', fill='steelblue') +
  geom_text(aes(label=round(MeanDecreaseGini,digits=1)),hjust=-0.1,color="deepskyblue4", size=4.0) +
  theme_classic() +
  theme(axis.title.x = element_text(face = "bold", color = "deepskyblue4", size = 15,vjust=-1)) +
  theme(axis.title.y = element_text(face = "bold", color = "deeppink4", size = 15,vjust=3)) +
  theme(axis.text.x = element_text(face="bold", color = "deepskyblue4", size = 13)) +
  theme(axis.text.y = element_text(face="bold", color = "deeppink4", size = 13)) +
  theme(plot.title = element_text(face="bold", color = "black", size = 20, vjust=3, lineheight=1.2,hjust=0.5 )) +
  theme(plot.margin=unit(c(1,1,1.5,1.2),"cm")) +
  labs(
    x     = "Importance",
    y     = "Feature",
    title = "Gini Importance for Top Features (MeanDecreaseGini>50) \n in Phylum Prediction Using Random Forest Model"
  )


###Create RF Model based only on the top 4 most important features (as defined MeanDecreaseGini)
phylum_classifier_top_features <- randomForest(x = dfTraining[, c("GGCC","ACCA","TTAG","TTTA")], y = as.factor(dfTraining$Phylum), ntree = 8000, importance = TRUE)

#Overview of Classifier (Top 4 features): OOB estimate of error rate is 1.38%
phylum_classifier_top_features


###Create RF model based only on the most important feature (as defined by MeanDecreaseGini): GGCC
phylum_classifier_GGCC<- randomForest(x = dfTraining[, "GGCC"], y = as.factor(dfTraining$Phylum), ntree = 8000, importance = TRUE)

#Overview of Classifier(single feature: GGCC): OOB estimate of error rate is 5.95%
phylum_classifier_GGCC


###Create RF model based only on the least important feature (as defined by MeanDecreaseGini): CTAC
phylum_classifier_CTAC<- randomForest(x = dfTraining[, "CTAC"], y = as.factor(dfTraining$Phylum), ntree = 8000, importance = TRUE)

#Overview of Classifier(single feature: CTAC): OOB estimate of error rate is 18.92%
phylum_classifier_CTAC




###REPEATING RANDOM FOREST FOR 3-MERs----

#Calculate k-mers of length 3 and append to dataframe
df_firmi_actino_k3 <- cbind(df_firmi_actino_k3, as.data.frame(trinucleotideFrequency(df_firmi_actino_k3$Sequence_16S2)))

#Convert Sequence_16S2 from a DNAStringSet back to a tibble dataframe
df_firmi_actino_k3$Sequence_16S2<-as.character(df_firmi_actino_k3$Sequence_16S2)

#Set seed so results are reproducible in the future
set.seed(118)

#Create validation data set for 3-mers by sampling 1000 records from each phylum
dfvalidation_k3<-df_firmi_actino_k3 %>% 
  group_by(Phylum)%>% 
  sample_n(1000)

#Set seed so results are reproducible in the future
set.seed(93)

#Create training dataset for 3-mers by sampling 2000 records from each phylum
dfTraining_k3 <- df_firmi_actino_k3%>%
  filter(!Title_16S %in% dfvalidation_k3$Title_16S) %>% 
  group_by(Phylum) %>%
  sample_n(2000)

#Build RF Classifier for 3-mers
phylum_classifier_k3 <- randomForest(x = dfTraining_k3[, 5:68], y = as.factor(dfTraining_k3$Phylum), ntree = 4000, importance = TRUE)

#See overview of classifier for training set: 0.25% OOB error estimate
phylum_classifier_k3

#Validation Set Assessment #1: Confusion Matrix

#Encode Phylum (the target categorical features) of validation data as factor with two levels. 
dfvalidation_k3$Phylum = factor(dfvalidation_k3$Phylum, levels = c("actinobacteria","firmicutes"))

#Create prediction using validation set
phylum_prediction_k3<-predict(phylum_classifier_k3, newdata=dfvalidation_k3[,5:68])

#Create a confusion matrix to evaluate the model's performance on the validation set
confusion_matrix_k3<-confusionMatrix(phylum_prediction_k3,dfvalidation_k3$Phylum)

#Output shows accuracy of 99.6%
confusion_matrix_k3



###REPEATING RANDOM FOREST FOR 2-MERs----


#Calculate k-mers of length 2 and append to dataframe
df_firmi_actino_k2 <- cbind(df_firmi_actino_k2, as.data.frame(dinucleotideFrequency(df_firmi_actino_k2$Sequence_16S2)))

#Convert Sequence_16S2 from a DNAStringSet back to a tibble dataframe
df_firmi_actino_k2$Sequence_16S2<-as.character(df_firmi_actino_k2$Sequence_16S2)

#Set seed so results are reproducible in the future
set.seed(80)

#Create validation data set for 2-mers by sampling 1000 records from each phylum
dfvalidation_k2<-df_firmi_actino_k2 %>% 
  group_by(Phylum)%>% 
  sample_n(1000)

#Set seed so results are reproducible in the future
set.seed(129)

#Create training dataset for 2-mers by sampling 2000 records from each phylum
dfTraining_k2 <- df_firmi_actino_k2%>%
  filter(!Title_16S %in% dfvalidation_k2$Title_16S) %>% 
  group_by(Phylum) %>%
  sample_n(2000) #why?

#Build RF Classifier for 2-mers
phylum_classifier_k2 <- randomForest(x = dfTraining_k2[, 5:20], y = as.factor(dfTraining_k2$Phylum), ntree = 4000, importance = TRUE)

#See overview of classifier for training set: 0.9% OOB error estimate
phylum_classifier_k2

#Validation Set Assessment of RF Model for 2-mers Using Confusion Matrix

#Encode Phylum (the target categorical features) of validation data as factor with two levels. 
dfvalidation_k2$Phylum = factor(dfvalidation_k2$Phylum, levels = c("actinobacteria","firmicutes"))

#Create prediction using validation set
phylum_prediction_k2<-predict(phylum_classifier_k2, newdata=dfvalidation_k2[,5:20])

#Create a confusion matrix to evaluate the model's performance on the validation set
confusion_matrix_k2<-confusionMatrix(phylum_prediction_k2,dfvalidation_k2$Phylum)

#Output shows accuracy of 99.05%
confusion_matrix_k2




####Classification Tree (using rpart package)----

#install.packages("rpart")
library("rpart")
#install.packages("rpart.plot")
library("rpart.plot")

#Extract k-mer and Phylum columns from dfTraining in order to more easily use rpart
df_Training_firmi_actino_sub <- dfTraining%>% 
  select(-Title_16S, -Sequence_16S, -Sequence_16S2)

#Extract k-mer and Phylum columns from dfvalidation in order to more easily use rpart
df_validation_firmi_actino_sub <- dfvalidation%>% 
  select(-Title_16S, -Sequence_16S, -Sequence_16S2)

#Fit an classification tree
rpart_tree<-rpart(formula=Phylum~., data= df_Training_firmi_actino_sub, method='class')

#Explanation for some of the most relevant argument choices in above model:
#formula=Phylum~. because we want to predict phylum using all other variables in the table (4-mer features) as predictors  
#method=class because this is a classification tree; if it were a regression tree we would use ANOVA
#parms=list('gini') left to default. By default, rpart uses gini impurity to select splits when performing classification which gives equal penalization of mislabeled target classes. If we wanted to train the tree to penalize the mislabeling of some target classes more than others, we could change the loss component of the parms parameter to a matrix via parms=list('loss')
#weights left unspecified because we don't want to ascribe higher/lower weights to particular features
#subset left unspecified because we wish to use all of rows in the fit
#na.action left unspecified because we pre-screened for missing data
#Cost left unspecified because we don't wish to more heavily penalize false positives or false negatives. If we had prominent class imbalances we might revisit this.


##Evaluate the Decision Tree

#Check the tree. Note: it has 7 nodes (see bracketed numbers)
rpart_tree

#View summary of the tree 
summary(rpart_tree)

#Predict the test dataset
rpart_prediction<-predict(rpart_tree,newdata=df_validation_firmi_actino_sub[,2:257], type='class')

#Build a contingency table of the counts at each combination of factor levels
rpart_evaluation<-table(df_validation_firmi_actino_sub$Phylum,rpart_prediction)

#View the outout. Note the model misclassified 26 Actinobacteria as Firmicutes, and misclassified 23 Firmicutes as Actinobacteria
rpart_evaluation

#Use a confusion matrix to evaluate the performance of the decision tree.
rpart_confusion_matrix<-confusionMatrix(rpart_prediction,df_validation_firmi_actino_sub$Phylum)

#Print the confusion; shows accuracy of 97.55%
print(rpart_confusion_matrix)

#Install and load packages to plot the tree
#install.packages("rattle")
library("rattle")

#Plot the tree using rattle package
fancyRpartPlot(model=rpart_tree, main="Decision Tree for Taxonomic Classification of \n Phylum (Actinobacteria or Firmicutes) Using 4-mer Features ",caption=" ",yshift=-13,palettes=c("Greys", "Oranges"))



####KNN Classifier----

#install packages
#install.packages("class")
library("class")

#Checking to see if the data needs to be normalized. Since all numerical values are within ~similar range, normalization is deemed not to be necessary.
summary(df_firmi_actino)

#set seed so results are reproducible in the future
set.seed(124)


###KNN#1: Using the same training and validation sets as defined for the RF models.

#Build KNN Classifier 
#k=3 chosen to obtain fast computation, reduce variance from noise, and ideally balance the risks of underfitting and overfitting. An odd number was selected because this is a binary classifier. It is expect that this may need to be increased, because while there isn't a single k-value that is optimal across all data sets, k=sqrt(number of data points) in a reported rule of thumb (Singh et al., 2017).
knn_prediction1<-knn(train=dfTraining[,5:260],test=dfvalidation[,5:260],cl=dfTraining$Phylum,k=3)

#Create and view confusion matrix for KNN
knn_confusion_matrix<-confusionMatrix(table(knn_prediction1,dfvalidation$Phylum))
knn_confusion_matrix


###KNN #2: Using new training and validation sets

###Define validation data set for KNN

#Assign either a 1 or a 2 to each row of the dataset. The Sample size is the number records in the dataset (8000). We assign 1s with a probability of 0.67 to create a training set with 2/3 of the records from the original data set, and assign 2's with a probability of 0.33 to create validation set with 1/3 of the records from the original dataset.
knn_sample <- sample(2, nrow(df_firmi_actino), replace=TRUE, prob=c(0.67, 0.33))

#Define the training data set for KNN
knn_training <- df_firmi_actino[knn_sample==1,5:260]

#Define the validation data set for KNN
knn_validation <- df_firmi_actino[knn_sample==2,5:260]

#Store phylum labels in factor vectors and divide them over the training and test sets
knn.trainlabels<-df_firmi_actino[knn_sample==1,3]
knn.validationlabels<-df_firmi_actino[knn_sample==2,3]

#Build the KNN Classifier
knn_prediction<-knn(train=knn_training,test=knn_validation,cl=knn.trainlabels,k=3)


##Evaluate the KNN Classifier

#Inspect the results of knn classifier
knn_prediction

#Put knn.validationlabels into a dataframe
df.knn.validationlabels<-data.frame(knn.validationlabels)

#Merge knn_prediction and knn.validationlabels
knn.pred.val<-data.frame(knn_prediction,knn.validationlabels)

#Specify column names for merge
names(knn.pred.val)<-c("Predicted Phylum","Observed Phylum")

#Inspect merge
knn.pred.val

#Further evaluate KNN performance

#Install and load gmodels package
install.packages("gmodels")
library(gmodels)

#Create contingency table while indicating that we do not want chi-square contribution of each cell to be included. Note that 1 Firmicutes was mislabelled as Actinobacteria.
CrossTable(x=knn.validationlabels, y=knn_prediction,prop.chisq=FALSE)

