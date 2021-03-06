# these functions use the ete3 package to manipulate the NCBI taxonomy
# this is used in the host depletion step and for summarising the annotations

# the first time this is used, it will download the NCBI taxonomy database into your home directory
from ete3 import NCBITaxa

# helper function to return the desired rank from a taxid

ncbi = NCBITaxa()

def get_desired_rank(taxid, desired_rank):
    lineage = ncbi.get_lineage(taxid)
    names = ncbi.get_taxid_translator(lineage)
    lineage2ranks = ncbi.get_rank(names)
    ranks2lineage = dict((rank,taxid) for (taxid, rank) in lineage2ranks.items())
    specific_taxid = ranks2lineage.get(desired_rank, '<not present>')
    if specific_taxid != '<not present>':
        return(list(ncbi.get_taxid_translator([specific_taxid]).values())[0])
    else:
        return('<not present>')

