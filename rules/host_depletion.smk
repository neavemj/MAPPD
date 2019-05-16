"""
Host depletion rules

These rules will map reads to host genetic data
and split the reads into those that match and those that don't
Using results from the rRNA mapping wasn't working particularly
well. Mainly because the SSU gene is too similar across species.
E.g. sheep and human are very similar, so the host species
gets mixed up.

Decided instead to do a small assembly on a subset of the data
and blast the results to find host.
"""

rule subset_mRNA_reads:
    message:
        """
        ** host_depletion **
        Taking a subset of 100,000 mRNA reads from {wildcards.sample}
        to be used for assembly and host identification
        """
    input:
        R1 = config["sub_dirs"]["depletion_dir"] + "/rRNA/{sample}_mRNA_1P.fastq",
        R2 = config["sub_dirs"]["depletion_dir"] + "/rRNA/{sample}_mRNA_2P.fastq",
    output:
        R1 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_100k_mRNA_1P.fastq",
        R2 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_100k_mRNA_2P.fastq",
    shell:
        """
        head \
            -n 400000 \
            {input.R1} \
            > {output.R1} && \
        head \
            -n 400000 \
            {input.R2} \
            > {output.R2}
        """

rule assemble_mRNA_subset:
    message:
        """
        ** host_depletion **
        Assembling small subset of {wildcards.sample} reads to identify host
        """
    input:
        R1 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_100k_mRNA_1P.fastq",
        R2 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_100k_mRNA_2P.fastq"
    output:
        out_fasta = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_sub_assembly/contigs.fasta",
    params:
        out_dir = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_sub_assembly"
    log:
        "logs/spades_sub_assembly/{sample}.log"
    benchmark:
        "benchmarks/" + config["sub_dirs"]["depletion_dir"] + "/spades_sub_assembly/{sample}.txt"
    threads: 16
    shell:
        """
        spades.py \
            -1 {input.R1} \
            -2 {input.R2} \
            -t {threads} \
            -o {params.out_dir} > {log}
        """

rule subset_subcontigs:
    message:
        """
        ** host_depletion **
        Gathering the 10 largest contigs from the sub-assembly
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_sub_assembly/contigs.fasta",
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.fasta",
    shell:
        # using the most abundant 10 contigs larger than 1000 bps for host identification
        # can experiment with these parameters if required
        """
        {config[program_dir]}/scripts/gather_contigs.py \
            -c {input} \
            -s 1000 \
            -n 10 \
            -o {output}
        """

rule blast_subcontigs:
    message:
        """
        ** host_depletion **
        Blasting the most abundant contigs from sub-assembly
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.fasta",
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.blastn",
    params:
        blast_nt = config["blast_nt"]
    threads: 16
    log:
        "logs/blast_sub_assembly/{sample}.log"
    benchmark:
        "benchmarks/" + config["sub_dirs"]["depletion_dir"] + "/blast_sub_assembly/{sample}.txt"
    shell:
        # in the output fmt, cols 6 and 7 need to be bitscore and taxid
        # for the scripts subset_blast.py and tally_organism_hits.py
        """
        blastn \
            -query {input} \
            -out {output} \
            -db {params.blast_nt} \
            -evalue 0.001 \
            -num_threads {threads} \
            -outfmt '6 \
                qseqid \
                sseqid \
                pident \
                length \
                evalue \
                bitscore \
                staxid \
                stitle'
        """

rule subset_subblast:
    message:
        """
        ** host_depletion **
        Retieving the 'best' hits for each {wildcards.sample} contig
        using the maximum bitscore
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.blastn",
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.blastn.best_hits",
    shell:
        """
        {config[program_dir]}/scripts/subset_blast.py \
            -b {input} \
            -o {output}
        """

rule tally_abundant_subspecies:
    message:
        """
        ** host_depletion **
        Calculating the most abundant species in the blast results for all samples
        """
    input:
        expand(config["sub_dirs"]["depletion_dir"] + "/host/{sample}_largest_contigs.blastn.best_hits", sample=config["samples"])
    output:
        # producing both wide and long format tables here
        # the wide will be used for the report, and the long for plotting in ggplot
        wide = config["sub_dirs"]["depletion_dir"] + "/host/largest_contigs.blastn.tax.wide",
        long = config["sub_dirs"]["depletion_dir"] + "/host/largest_contigs.blastn.tax.long"
    shell:
        """
        {config[program_dir]}/scripts/tally_organism_hits.py \
            -b {input} \
            -t {output.wide} \
            -l {output.long}
        """

rule associate_hostTaxid_genbank:
    message:
        """
        ** host_depletion **
        Retreiving genbank ids for the most abundant species
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/largest_contigs.blastn.tax.wide"
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.ids"
    params:
        nt_to_taxids = config["nt_to_taxids"],
        hosts_to_download = config["hosts_to_download"]
    benchmark:
        "benchmarks/" + config["sub_dirs"]["depletion_dir"] + "/grep_nucl_gb_ids/generic.txt"
    shell:
        # -w means only match whole words - don't want part of the taxid matching another one
        # cuts the first column (taxids), removes header,
        # and retrieves as many host taxids as required,
        """
        grep \
            -w \
            -f <(cut -f 1 {input} | tail -n +2 | head -n {params.hosts_to_download}) \
            {params.nt_to_taxids} \
            > {output}
        """

rule extract_host_nucl:
    message:
        """
        ** host_depletion **
        Extracting host nucleotide sequence from the nt database
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.ids"
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.fasta"
    params:
        blast_nt = config["blast_nt"]
    log:
        "logs/extract_nucl_gb_fasta/accessions_not_found.log"
    benchmark:
        "benchmarks/" + config["sub_dirs"]["depletion_dir"] + "/extract_nucl_gb_fasta/generic.txt"
    shell:
        # if this command doesn't find an accesion number (often)
        # it prints an error and returns an exit code of 1
        # this stops snakemake working
        # I want it to keep running even if some accessions weren't found
        # so the '|| true' bit ensures it returns a successful exit code
        """
        blastdbcmd \
            -db {params.blast_nt} \
            -entry_batch <(cut -f 1 -d " " {input}) \
            > {output} 2> {log} || true
        """

rule build_host_bowtiedb:
    message:
        """
        ** host_depletion **
        Building a bowtie2 database from host nucleotide sequence
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.fasta"
    output:
        # bowtie2-build needs a basename for the database
        # usually I just give it the same name as the input
        # and it appends several *bt2 files
        # will trick snakemake by using this as an output even though
        # I won't use it in the shell command
        config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.fasta.1.bt2"
    shell:
        # use the same name for basename reference database
        """
        bowtie2-build \
            {input} \
            {input} > /dev/null
        """

rule bowtie_to_host:
    message:
        """
        ** host_depletion **
        Mapping {wildcards.sample} mRNA reads to host database
        """
    input:
        R1 = config["sub_dirs"]["depletion_dir"] + "/rRNA/{sample}_mRNA_1P.fastq",
        R2 = config["sub_dirs"]["depletion_dir"] + "/rRNA/{sample}_mRNA_2P.fastq",
        db_trick = config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.fasta.1.bt2"
    output:
        sam_fl = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sam"
    params:
        host_db = config["sub_dirs"]["depletion_dir"] + "/host/host_nucl_nt.fasta"
    log:
        "logs/bowtie_host/{sample}.log"
    benchmark:
        "benchmarks/" + config["sub_dirs"]["depletion_dir"] + "/bowtie_host/{sample}.txt"
    threads:
        16
    shell:
        """
        bowtie2 \
            -x {params.host_db} \
            -1 {input.R1} \
            -2 {input.R2} \
            -p {threads} \
            -S {output.sam_fl} 2> {log}
        """

rule host_sam_to_bam:
    message:
        """
        ** host_depletion **
        Converting {wildcards.sample} host sam file to bam
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sam"
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.bam"
    threads: 8
    shell:
        """
        samtools view \
            -@ {threads} \
            -S -b \
            {input} > {output}
        """

rule host_get_unmapped:
    message:
        """
        ** host_depletion **
        Collecting {wildcards.sample} reads that did not map to host sequences
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.bam"
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host_depleted.bam"
    threads: 8
    shell:
        # -f 13 should get reads where neither pair mapped (UNMAP & MUNMAP)
        """
        samtools view \
            -@ {threads} \
            -b \
            -f 13 \
            {input} > {output}
        """

rule host_sam_to_fastq:
    message:
        """
        ** host_depletion **
        Converting {wildcards.sample} host depleted sam file to fastq files
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host_depleted.bam"
    output:
        R1 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host_depleted_1P.fastq",
        R2 = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host_depleted_2P.fastq"
    threads: 8
    shell:
    # the dev null bit discards unpaired reads
    # the -F bit ensures the mates are paired
        """
        samtools fastq \
            -@ {threads} \
            -1 {output.R1} \
            -2 {output.R2} \
            -0 /dev/null \
            -s /dev/null \
            -n \
            -F 0x900 \
            {input} 2> /dev/null
        """

rule summarise_rRNA_host_mapping:
    message:
        """
        ** host_depletion **
        Summarising number of reads mapped to rRNA and host databases
        """
    input:
        lsu = expand("logs/bowtie_LSU/{sample}.log", sample=config["samples"]),
        ssu = expand("logs/bowtie_SSU/{sample}.log", sample=config["samples"]),
        # note the host results are no longer used down-stream
        host = expand("logs/bowtie_host/{sample}.log", sample=config["samples"])
    output:
        "logs/mapping_summary.tsv"
    shell:
        """
        {config[program_dir]}/scripts/summarise_mapping_results.py \
            -l {input.lsu} \
            -s {input.ssu} \
            -t {input.host} \
            -o {output}
        """

# this rule was copied over from the assembly.smk rules
# need to do this so I can add the host stats to the overall tax stats
rule host_mapping_stats:
    message:
        """
        ** host_depletion **
        Tallying statistics on {wildcards.sample} reads mapped to the host
        """
    input:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.bam"
    output:
        sorted_bam = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sorted.bam",
        stats = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sorted.idxstats",
        depth = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sorted.depth",
    threads: 16
    shell:
        # this will sort > index > idxstats > sort by most mapped reads
        """
        samtools sort \
            -@ {threads} \
            {input} > {output.sorted_bam} && \
        samtools index \
            -@ {threads} \
            {output.sorted_bam} && \
        samtools idxstats \
            -@ {threads} \
            {output.sorted_bam} | \
            sort -nrk 3 \
            > {output.stats} && \
        samtools depth \
            {output.sorted_bam} \
            > {output.depth}
        """

# required so that I can add the host reads onto my
# tax barcharts in the report
# had to modify the 'tally_organism_abundance.py' script here
# because I'm not adding reads per contig - rather per host taxid
rule summarise_host_abundance:
    message:
        """
        ** host_depletion **
        summarise abundance stats for the host species
        """
    input:
        wide = config["sub_dirs"]["depletion_dir"] + "/host/largest_contigs.blastn.tax.wide",
        stats = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sorted.idxstats",
        depth = config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.sorted.depth",
    output:
        config["sub_dirs"]["depletion_dir"] + "/host/{sample}_host.blastn.abundance",
    shell:
        """
        {config[program_dir]}/scripts/tally_host_abundance.py \
            -w {input.wide} \
            -i {input.stats} \
            -d {input.depth} \
            -o {output} \
        """





