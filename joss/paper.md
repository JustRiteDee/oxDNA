---
title: 'oxDNA: coarse-grained simulations of nucleic acids made simple'
tags:
  - C++
  - Python
  - DNA
  - DNA nanotechnology
  - Molecular simulations
authors:
  - name: Erik Poppleton
    orcid:  0000-0002-5146-5970 
    affiliation: 1
  - name: Michael Matthies
    orcid: 
    affiliation: 1
  - name: Debesh Mandal
    orcid:
    affiliation: 2
  - name: Flavio Romano
    orcid: 
    affiliation: 3
  - name: Petr Šulc
    orcid: 0000-0003-1565-6769
    affiliation: 1
  - name: Lorenzo Rovigatti^[Corresponding author]
    orcid: 0000-0001-5017-2829
    affiliation: "4, 5"
affiliations:
 - name: School of Molecular Sciences and Center for Molecular Design and Biomimetics, The Biodesign Institute, Arizona State University, United States of America
   index: 1
 - name: Department of Materials, Imperial College London, United Kingdom
   index: 2
 - name: Dipartimento di Scienze Molecolari e Nanosistemi, Universitá Ca Foscari di Venezia, Italy
   index: 3
 - name: Department of Physics, Sapienza University of Rome, Italy
   index: 4
 - name: CNR-ISC UoS Sapienza, Rome, Italy
   index: 5
date: 08 May 2022
bibliography: paper.bib
---

# Summary

The fields of DNA and RNA nanotechnology have progressed from pioneering, proof-of-principle experiments to fully-fledged applications in material science, biology and medicine. These applications exploit the intrinsic programmability of nucleic acids to generate nano- and even micro-scale structures with tailored properties. However, the design of the DNA/RNA sequences that self-assemble into a desired structure is not straightforward and often relies on expensive trial-and-error experimental protocols. A complementary approach is provided by computer simulations, which can model biomacromolecules at different levels of detail, ranging from atomistic to continuous, and can be leveraged to investigate the whole range of time- and length-scales relevant for applications. Here we present `oxDNA`, a software package that has been designed to efficiently run coarse-grained simulations of DNA and RNA and also features an analysis suite aimed at post-processing the analysis of oxDNA/oxRNA trajectories.

# Statement of need

The simulation of nucleic acids has become an important tool from the fundamental point of view to understand how these biomacromolecules behave and, from an application standpoint, to predict their behaviour under specific conditions [@DNA_simulation_review]. The ideal model for each specific problem, and therefore the level of detail with which DNA and RNA are to be described, depends on the time and length scales of interest: at one end of the spectrum there is quantum chemistry modelling, which can be used to probe the microscopic properties of a small number of nucleotides [@quantum_DNA], while at the other end there are continuum descriptions based on polymer theories such as the worm-like chain model [@WLC] that can be used to study the behaviour of long DNA strands. A middle road is provided by coarse-grained models that describe nucleic acids at the nucleotide level [@oxDNA_review]. At this level of detail the oxDNA, oxDNA2 and oxRNA models has become popular choices to investigate the dynamics, thermodynamics and self-assembly behaviour of DNA and RNA systems [@oxRNA; @oxDNA_primer], and have been used in more than [a hundred publications](https://www.webofscience.com/wos/author/record/14753) to date.

# Functionality

Here we present an updated version of the `oxDNA` code, an efficient, multi-technique simulation package written in C++ and specifically developed to carry out simulations of coarse-grained nucleic acid systems described with the oxDNA and oxRNA models. The package, which is named after the original oxDNA model, can perform both molecular dynamics (MD) and Monte Carlo (MC) simulations. MD simulations can be run on single CPUs or single CUDA-enabled GPUs, while MC simulations, which can only be run serially, can exploit the Virtual Move Monte Carlo algorithm [@VMMC] to greatly speed-up equilibration and sampling, and Umbrella Sampling biasing to efficiently obtain free-energy profiles. The package also features a Forward-Flux Sampling interface to study the kinetics of rare events [@FFS], and makes it possible to alter the behaviour of the systems by adding *external forces* that can be used, for instance, to pull on or apply torques to strands or confine nucleotides within semi-planes or spheres.

The package can also be used to compute nucleic-acid-related quantities such as the energy due to hydrogen bonding or stacking, the distance between groups of nucleotides, the list of hydrogen-bonded nucleotides or of over-stretched bonds, and much more. The analysis can be performed while the simulation is running or on trajectory files produced by finished simulations. 

The version of the code we present here is hosted on GitHub and has been modernised with respect to earlier versions (see *e.g.* [@rovigatti2015comparison]) to exploit the C++-14 and CUDA 11 standards. This new version also includes `oxpy`, a Python library which makes it possible to control the behaviour of the simulation using Python scripts, as well as examples that demonstrate how to leverage `oxpy` to write backends to run replica-exchange [@REMD] and well-tempered metadynamics [@metadynamics] simulations which are popular techniques in modern molecular dynamics to improve sampling efficiency.

The simulation engine is complemented by an updated version of `oxDNA_analysis_tools` (`oat`) [@oat], a Python library aimed at facilitating the analysis of oxDNA/oxRNA trajectories. `Oat` provides numerous common simulation trajectory analysis tools including alignment, mean structures, subsetting trajectories, distances between nucleotides, interduplex angles, and comparison in hydrogen bonding patterns between the trajectory and an idealised structure. `Oat` was previously published as a standalone Python package [@oat], however, since the initial publication, substantial improvements have been made including a new Cython-based random access file parser which accelerated computation of mean structures by more than 10x, and close integration with `oxpy`, which sped up and simplified calculation of nucleotide interactions by more than 100x. `Oat` was developed with the intention of facilitating other, more specific, analysis tasks. The file readers and utility functions are available for import into users' Python projects and the scripts themselves are well-commented to serve as examples for users to extend them for their own needs.

# Related software

Molecular dynamics simulations of oxDNA and oxRNA can also be performed with the `LAMMPS` software package, whose efficient parallel-computing algorithms make it possible to simulate large systems on HPC clusters [@oxDNA_LAMMPS]. However, at the moment it lacks GPU support, it cannot be used to build free-energy profiles by biasing discrete reaction coordinates (*e.g.* number of correct basepairs) and there are no tools to analyse LAMMPS-generated trajectories such as `oat` [@oat] or `oxview` [@bohlin2022design]. In addition, the LAMMPS engine supports many more (often oxDNA-unrelated) options, which may make it harder to correctly setup oxDNA simulations compared to `oxDNA`. Therefore, the `oxDNA` simulation package presented here complements the `LAMMPS` version, which also bears the "oxdna" name, rather than competing with it.

Finally, we note that there are many software packages that either use `oxDNA` or take as input, output or manipulate configurations generated with the `oxDNA` package. The list comprises `MrDNA` [@MrDNA], `Adenita` [@adenita], `TacoxDNA` [@tacoxDNA], [`oxDNA.org`](https://oxdna.org/) [@oxDNA.org], `scadnano` [@scadnano], `MagicDNA` [@magicdna] and `ENSnano` [@ENSnano].

# Acknowledgements

We acknowledge contributions from R. Harrison, C. Matek, F. Randisi, W. Smith and Benedict E. K. Snodin. LR acknowledges support from the CINECA award under the ISCRA initiative for the availability of high performance computing resources and support (Iscra B "AssoPoN"), PS acknowledges support from ONR grant no N000142012094, and DM acknowledges support from the Engineering and Physical Sciences Research Council [grant number EP/N509486/1].

# References

