/*
 * FSInteraction.cpp
 *
 *  Created on: 14/mar/2013
 *      Author: lorenzo
 */

#include "FSInteraction.h"
#include "../Particles/PatchyParticle.h"
#include "../Utilities/Utils.h"

#include <string>

using namespace std;

template <typename number>
FSInteraction<number>::FSInteraction() : BaseInteraction<number, FSInteraction<number> >(), _N_patches(-1), _N_patches_B(-1), _N_A(0), _N_B(0), _N(-1), _one_component(false) {
	this->_int_map[FS] = &FSInteraction<number>::_two_body;

	_lambda = 1.;
}

template <typename number>
FSInteraction<number>::~FSInteraction() {

}

template<typename number>
void FSInteraction<number>::get_settings(input_file &inp) {
	IBaseInteraction<number>::get_settings(inp);

	getInputInt(&inp, "FS_N", &_N_patches, 1);
	getInputInt(&inp, "FS_N_B", &_N_patches_B, 0);
	getInputBool(&inp, "FS_one_component", &_one_component, 0);

	getInputNumber(&inp, "FS_lambda", &_lambda, 0);
}

template<typename number>
void FSInteraction<number>::init() {
	_rep_rcut = pow(2., 1./6.);
	_sqr_rep_rcut = SQR(_rep_rcut);
	_rep_E_cut = -4./pow(_sqr_rep_rcut, 6) + 4./pow(_sqr_rep_rcut, 3);

	_sigma_ss = 0.4;
	_rcut_ss = 1.5*_sigma_ss;

	_patch_rcut = _rcut_ss;
	_sqr_patch_rcut = SQR(_patch_rcut);

	this->_rcut = 1. + _patch_rcut;
	this->_sqr_rcut = SQR(this->_rcut);

	number B_ss = 1. / (1. + 4.*SQR(1. - _rcut_ss/_sigma_ss));
	_A_part = -1. / (B_ss - 1.) / exp(1. / (1. - _rcut_ss/_sigma_ss));
	_B_part = B_ss * pow(_sigma_ss, 4.);

	OX_LOG(Logger::LOG_INFO, "FS parameters: lambda = %lf, A_part = %lf, B_part = %lf", _lambda, _A_part, _B_part);
}

template<typename number>
void FSInteraction<number>::allocate_particles(BaseParticle<number> **particles, int N) {
	for(int i = 0; i < N; i++) {
		int i_patches = (i < _N_A) ? _N_patches : _N_patches_B;
		particles[i] = new PatchyParticle<number>(i_patches);
	}
	_bonds.resize(N);
	_N = N;
}

template<typename number>
number FSInteraction<number>::pair_interaction(BaseParticle<number> *p, BaseParticle<number> *q, LR_vector<number> *r, bool update_forces) {
	number energy = pair_interaction_bonded(p, q, r, update_forces);
	energy += pair_interaction_nonbonded(p, q, r, update_forces);
	return energy;
}

template<typename number>
number FSInteraction<number>::pair_interaction_bonded(BaseParticle<number> *p, BaseParticle<number> *q, LR_vector<number> *r, bool update_forces) {
	// reset _bonds. This is beyond horrible
	if(q == P_VIRTUAL && p->index == 0) {
		for(int i = 0; i < _N; i++)	_bonds[i].clear();
	}

	return (number) 0.f;
}

template<typename number>
number FSInteraction<number>::pair_interaction_nonbonded(BaseParticle<number> *p, BaseParticle<number> *q, LR_vector<number> *r, bool update_forces) {
	LR_vector<number> computed_r(0, 0, 0);
	if(r == NULL) {
		computed_r = q->pos.minimum_image(p->pos, this->_box_side);
		r = &computed_r;
	}

	return _two_body(p, q, r, update_forces);
}

template<typename number>
void FSInteraction<number>::generate_random_configuration(BaseParticle<number> **particles, int N, number box_side) {
	number old_rcut = this->_rcut;
	this->_rcut = 1;

	this->_create_cells(particles, N, box_side, true);

	for(int i = 0; i < N; i++) {
		BaseParticle<number> *p = particles[i];
		bool inserted = false;
		int cell_index;
		do {
			p->pos = LR_vector<number>(drand48()*box_side, drand48()*box_side, drand48()*box_side);
			cell_index = (int) ((p->pos.x / box_side - floor(p->pos.x / box_side)) * (1.f - FLT_EPSILON) * this->_cells_N_side);
			cell_index += this->_cells_N_side * ((int) ((p->pos.y / box_side - floor(p->pos.y / box_side)) * (1.f - FLT_EPSILON) * this->_cells_N_side));
			cell_index += this->_cells_N_side * this->_cells_N_side * ((int) ((p->pos.z / box_side - floor(p->pos.z / box_side)) * (1.f - FLT_EPSILON) * this->_cells_N_side));

			inserted = true;
			for(int c = 0; c < 27; c ++) {
				int j = this->_cells_head[this->_cells_neigh[cell_index][c]];
				while (j != P_INVALID) {
					BaseParticle<number> *q = particles[j];
					if(p->pos.minimum_image(q->pos, box_side).norm() < SQR(this->_rcut)) inserted = false;
					j = this->_cells_next[q->index];
				}
			}
		} while(!inserted);

		int old_head = this->_cells_head[cell_index];
		this->_cells_head[cell_index] = i;
		this->_cells_index[i] = cell_index;
		this->_cells_next[i] = old_head;

		p->orientation.v1 = Utils::get_random_vector<number>();
		p->orientation.v2 = Utils::get_random_vector<number>();
		p->orientation.v3 = Utils::get_random_vector<number>();
		Utils::orthonormalize_matrix<number>(p->orientation);
	}

	this->_rcut = old_rcut;
	this->_delete_cell_neighs();
}

template<typename number>
void FSInteraction<number>::read_topology(int N, int *N_strands, BaseParticle<number> **particles) {
	*N_strands = N;

	std::ifstream topology(this->_topology_filename, ios::in);
	if(!topology.good()) throw oxDNAException("Can't read topology file '%s'. Aborting", this->_topology_filename);
	char line[512];
	topology.getline(line, 512);
	topology.close();
	sscanf(line, "%*d %d\n", &_N_A);
	_N_B = N - _N_A;
	if(_N_B > 0 && _N_patches_B == -1) throw oxDNAException("Number of patches of species B not specified");

	allocate_particles(particles, N);
	for (int i = 0; i < N; i ++) {
	   particles[i]->index = i;
	   particles[i]->type = (i < _N_A) ? P_A : P_B;
	   particles[i]->btype = (i < _N_A) ? P_A : P_B;
	   particles[i]->strand_id = i;
	}
}

template<typename number>
void FSInteraction<number>::check_input_sanity(BaseParticle<number> **particles, int N) {
	if(_N_B > 0 && _one_component) throw oxDNAException("One component simulations should have topologies implying that no B-particles are present");
}

template class FSInteraction<float>;
template class FSInteraction<double>;
