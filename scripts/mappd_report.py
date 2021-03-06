#!/usr/bin/env python

"""
Generate a html report for the mappd pipeline
Will generate a report specific to the files provided
For example, if the pipeline is run with only the trinity assembler,
this report will automatically only include results from
that assembly
"""

import sys, os
from snakemake.report import data_uri_from_file
import maketable

# this way the report should work no matter what pipeline components are run
# and I'll also be able to refer to them easily

def generate_report(config="", dag_graph="",
                    bench_time="", bench_mem="",
                    technical_summary="",
                    overall_figure = "",
                    sample_abundances = "",
                    spades_assembly="", spades_bandage="",
                    trinity_assembly="", trinity_bandage="",
                    spades_diamond="",
                    trinity_diamond="",
                    spades_blastn="",
                    trinity_blastn="",
                    ):


    # if a superkingdom is not detected, the figs and tables won't be created
    # e.g. if no viruses in a sample, there won't be any figures for them
    # will go through and check which ones exist
    potential_taxa_files = {
        "euk_figure": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.euk.png",
        "euk_table": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.euk.tsv",
        "bac_figure": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.bac.png",
        "bac_table": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.bac.tsv",
        "vir_figure": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.vir.png",
        "vir_table": config["sub_dirs"]["annotation_dir"] + "/diamond/diamond_blastx_abundance_top10.vir.tsv",
    }

    taxa_files = {}
    for taxa in potential_taxa_files:
        if os.path.isfile(potential_taxa_files[taxa]):
            taxa_files[taxa] = potential_taxa_files[taxa]

    # if a taxa is not detected, want some generic text explaining this

    not_detected = """

|

*{}*
---------------------

NONE DETECTED.

No {} sequences were detected with the parameters, software, strategy and
databases used here. This does not necessary mean that they are not present,
only that they were not detected with this particular pipeline.

Organisms are more likely to escape detection if they are low in abundance
(might get dropped in the assembly steps) or if they don't have close matches
in the NCBI databases (might get missed in the classification steps).

    """

    report = """

.. raw:: html

    <div id="nav">


.. contents:: MAPPD: Metagenomic Analysis Pipeline for Pathogen Discovery

.. raw:: html

    </div>

|
|

_______

    """

    report += """

1.   Introduction
==================
MAPPD is a general pipeline for the identification of organisms in a metagenomic sample,
although it is targeted toward the identification of pathogens.
The pipeline uses a strategy of read quality trimming, host identification,
read assembly, and annotation using various blast and diamond searches.
MAPPD does not require prior information about the sample (e.g. host),
as this information is determined by classifying read sub-sets.

**Important**
---------------
Metagenomic analysis can be a useful technology for screening samples in cases
where a pathogen is unknown. However, the classication of sequence fragments
based on the highest identity in a database does not necessarily mean that a
pathogen is present, only that this is the 'best' match. This report provides
the percent identity of database hits and the location of the particular contigs.
It may be necessary to check important classifications manually.
Additional lab-based tests are required to confirm pathogen identification.

|
|

_________

2.   Technical Summary
========================
The important parameters used in this pipeline are given below, including sample
files analysed, start and end times, and software versions.

"""

    with open(technical_summary) as fl:
        tech_string = fl.read()
    report += tech_string + """

|

"""

    report += """

|
|

_________

3.   Data Quality and Overall Classifications
===============================================
The raw data were trimmed for quality and adapters using `Trimmomatic`_.
The cleaned reads were then aligned to the SILVA ribosomal RNA databases,
including the Long Sub Unit (LSU) and Small Sub Unit (SSU) categories,
and matching reads were removed.

The remaining reads were then classified using iterative assemblies,
blasts and diamond searches. Reads that could not be classified after these
processes are shown as the grey 'Unannotated' bar below.

.. _Trimmomatic: http://www.usadellab.org/cms/?page=trimmomatic

    """
    report += "\t.. image:: " + data_uri_from_file(overall_figure) + "\n"

    if spades_bandage:
        report += """

|
|

________

Assembly
=================
The reads were assembled using SPAdes.
The figure below gives a representation of the scaffolds with at least 10x coverage

"""
        # NOTE: spades_bandage is a 'named list' due to wildcard expansion
        # thus, have to take first element of list to get str for data_uri
        report += "\t.. image:: " + data_uri_from_file(spades_bandage[0]) + "\n"

    if trinity_bandage:
        report += """
The reads were assembled using Trinity.
The figure below gives a representation of the scaffolds with at least 10x coverage

"""
        # NOTE: spades_bandage is a 'named list' due to wildcard expansion
        # thus, have to take first element of list to get str for data_uri
        report += "\t.. image:: " + data_uri_from_file(trinity_bandage[0]) + "\n"

    if "euk_figure" in taxa_files:
        report += """

|
|

________

4.   Summary Classifications
=============================

The figures and tables below provide summary classifications for all samples
that were analysed in this run. Usually this includes the most abundant 10
organisms from Eukaryotes, Bacteria and Viruses. If you would like more detailed
information on individual classifications, or to download sequence data associated
with particular organisms, see section `5.  Per Sample Classifications`_.


*Eukaryotes*
---------------
The figure below shows the top 10 most abundant Eukaryotic organisms,
including how many reads mapped to each organism from each sample.

"""
        report += "\t.. image:: " + data_uri_from_file(taxa_files["euk_figure"]) + "\n"

        report += """

|

The table shows how many reads were assigned to each organism, which family
the organism belongs to, and gives the read count for each sample.


"""

        euk_string = maketable.make_table_from_csv(taxa_files["euk_table"], sep="\t")
        report += euk_string + "\n"
    else:
        report += not_detected.format("Eukaryotes", "eukaryote")

    if "bac_figure" in taxa_files:
        report += """

|

*Bacteria*
---------------
The figure below shows the top 10 most abundant bacteria,
including how many reads mapped to each organism from each sample.

"""
        report += "\t.. image:: " + data_uri_from_file(taxa_files["bac_figure"]) + "\n"

        report += """

|

The table shows how many reads were assigned to each organism, which family
the organism belongs to, and gives the read count for each sample.

"""

        bac_string = maketable.make_table_from_csv(taxa_files["bac_table"], sep="\t")
        report += bac_string + "\n"
    else:
        report += not_detected.format("Bacteria", "bacteria")

    if "vir_figure" in taxa_files:
        report += """

|

*Viruses*
---------------
The figure below shows the top 10 most abundant viruses (if at least 10 were detected)
including how many reads mapped to each organism from each sample.

"""
        report += "\t.. image:: " + data_uri_from_file(taxa_files["vir_figure"]) + "\n"

        report += """

|

The table shows how many reads were assigned to each organism, which family
the organism belongs to, and gives the read count for each sample.

"""

        vir_string = maketable.make_table_from_csv(taxa_files["vir_table"], sep="\t")
        report += vir_string + "\n"
    else:
        report += not_detected.format("Viruses", "virus")




    if sample_abundances:
        report += """

|
|

________

5.   Per Sample Classifications
===============================

This section contains the complete classiciation reports for each sample.
Again, they are divided into Eukaryotes, Bacteria and Viruses.
The tables show the classification of each sequence at the kingdom,
family and species level, and provide the number of reads that were
classified to that taxa. This number is also used to calculate
the percentage of reads mapped as a fraction of all high-quality reads in
the dataset. In addition, the "Sequences" column provides a download link
for all sequences classified to that particular organism (often there will
be several).

|

"""
        for sample in sample_abundances:
            report += """

{}
--------------------------------------

""".format(os.path.basename(sample).split("_")[0])

            # I've already created a ReST table using 'abundance_ReST.py'
            # just want to insert that text directly here
            with open(sample) as fl:
                samp_string = fl.read()
            report += samp_string + """


|
|

________

"""


    if dag_graph:
        report += """

|
|

__________

Detailed DAG graph of pipeline structure
===========================================
A Directed Acyclic Graph (DAG) graph of the steps carried out in this pipeline is given below

"""
        report += "\t.. image:: " + data_uri_from_file(dag_graph) + "\n"

    if bench_time:
        report += """

|
|

________

Benchmarks
=================
The time taken for each process, and each sample, is given below

"""
        report += "\t.. image:: " + data_uri_from_file(bench_time) + "\n"

    if bench_mem:
        report += """

|

The maximum memory required for each process, and each sample, is given below

"""
        report += "\t.. image:: " + data_uri_from_file(bench_mem) + "\n"

    return(report)