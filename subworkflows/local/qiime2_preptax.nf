/*
 * Training of a classifier with QIIME2
 */

include { UNTAR                 } from '../../modules/nf-core/untar/main'
include { GZIP_DECOMPRESS       } from '../../modules/local/gzip_decompress.nf'
include { FORMAT_TAXONOMY_QIIME } from '../../modules/local/format_taxonomy_qiime'
include { QIIME2_EXTRACT        } from '../../modules/local/qiime2_extract'
include { QIIME2_TRAIN          } from '../../modules/local/qiime2_train'

workflow QIIME2_PREPTAX {
    take:
    ch_qiime_ref_taxonomy //channel, list of files
    val_qiime_ref_taxonomy //val
    FW_primer //val
    RV_primer //val

    main:
    ch_qiime2_preptax_versions = Channel.empty()

    if (params.qiime_ref_tax_custom) {
        if ("${params.qiime_ref_tax_custom}".contains(",")) {
            ch_qiime_ref_taxonomy
                .map { filepath ->
                    candidate = file(filepath, checkIfExists: true)
                    if (filepath.endsWith(".gz")) {
                        GZIP_DECOMPRESS(ch_qiime_ref_tax_branched.gzip)
                        ch_qiime2_preptax_versions = ch_qiime2_preptax_versions.mix(GZIP_DECOMPRESS.out.versions)

                        return GZIP_DECOMPRESS.out.ungzip
                    } else if (filepath.endsWith(".fna") || filepath.endsWith(".tax")) {
                        return candidate
                    } else {
                        error "$filepath is neither a compressed or decompressed sequence or taxonomy file. Please review input."
                    }
                }.set { ch_qiime_db_files }

            ch_ref_database = ch_qiime_db_files.collate(2)
        } else {
            ch_qiime_ref_taxonomy
                .branch {
                    tar: it.isFile() && ( it.getName().endsWith(".tar.gz") || it.getName().endsWith (".tgz") )
                    dir: it.isDirectory()
                    failed: true
                }.set { ch_qiime_ref_tax_branched }
            ch_qiime_ref_tax_branched.failed.subscribe { error "$it is neither a directory nor a file that ends in '.tar.gz' or '.tgz'. Please review input." }

            UNTAR (
                ch_qiime_ref_tax_branched.tar
                    .map {
                        db ->
                            def meta = [:]
                            meta.id = val_qiime_ref_taxonomy
                            [ meta, db ] } )
            ch_qiime_db_dir = UNTAR.out.untar.map{ it[1] }
            ch_qiime_db_dir = ch_qiime_db_dir.mix(ch_qiime_ref_tax_branched.dir)

            ch_ref_database_fna = ch_qiime_db_dir.map{ dir ->
                files = file(dir.resolve("*.fna"), checkIfExists: true)
            } | filter {
                if (it.size() > 1) log.warn "Found multiple fasta files for QIIME2 reference database."
                it.size() == 1
            }
            ch_ref_database_tax = ch_qiime_db_dir.map{ dir ->
                files = file(dir.resolve("*.tax"), checkIfExists: true)
            } | filter {
                if (it.size() > 1) log.warn "Found multiple tax files for QIIME2 reference database."
                it.size() == 1
            }

            ch_ref_database = ch_ref_database_fna.combine(ch_ref_database_tax)
        }
    } else {
        FORMAT_TAXONOMY_QIIME ( ch_qiime_ref_taxonomy.collect() )

        ch_ref_database = FORMAT_TAXONOMY_QIIME.out.fasta.combine(FORMAT_TAXONOMY_QIIME.out.tax)
    }

    ch_ref_database
        .map {
            db ->
                def meta = [:]
                meta.FW_primer = FW_primer
                meta.RV_primer = RV_primer
                [ meta, db ] }
        .set { ch_ref_database }
    QIIME2_EXTRACT ( ch_ref_database )
    QIIME2_TRAIN ( QIIME2_EXTRACT.out.qza )

    emit:
    classifier      = QIIME2_TRAIN.out.qza
    versions        = QIIME2_TRAIN.out.versions
}

