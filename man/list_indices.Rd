% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/list_indices.R
\name{list_indices}
\alias{list_indices}
\title{List spectral indices}
\usage{
list_indices(values, pattern = "")
}
\arguments{
\item{values}{A vector of attributes which will be returned, being
one or more within the followings:
\itemize{
\item \code{n_index}: internal index identifiers;
\item \code{name}: index name;
\item \code{longname}: index description;
\item \code{link}: URL to the index description page;
\item \code{s2_formula}: expression containing the formula to compute the index;
\item \code{s2_formula_mathml}: MathML version of the formula.
}}

\item{pattern}{A regular expression on index names.}
}
\value{
A data.frame with the required information. The table contains
also the following attributes:
\itemize{
\item \code{creation_date}: timestamp of the creation date of the indices archive;
\item \code{fidolasen_version}: version of the \code{fidolasen} package used to
create the indices archive.
}
}
\description{
Return a table with attributes of the spectral indices
computable with the package.
}
\note{
License: GPL 3.0
}
\examples{
\dontrun{
list_indices(c("name","longname"))
}
}
\author{
Luigi Ranghetti, phD (2017) \email{ranghetti.l@irea.cnr.it}
}
