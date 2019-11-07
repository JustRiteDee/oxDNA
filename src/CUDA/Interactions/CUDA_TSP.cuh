/* System constants */
__constant__ int MD_N[1];
__constant__ int MD_N_stars[1];
__constant__ int MD_N_per_star[1];
__constant__ int MD_n_forces[1];

__constant__ float MD_sqr_rfene[1];
__constant__ float MD_sqr_rfene_anchor[1];
__constant__ float MD_sqr_rcut[1];
__constant__ float MD_sqr_rep_rcut[1];
__constant__ float MD_TSP_lambda[1];
__constant__ int MD_TSP_n[1];
__constant__ bool MD_TSP_only_chains[1];

__constant__ bool MD_yukawa_repulsion[1];
__constant__ float MD_TSP_yukawa_A[1];
__constant__ float MD_TSP_yukawa_xi[1];
__constant__ float MD_yukawa_E_cut[1];

#include "../cuda_utils/CUDA_lr_common.cuh"

__device__ bool is_anchor(int index) {
	return ((index % MD_N_per_star[0]) == 0);
}

__device__ void _nonbonded(c_number4 &r, int int_type, c_number4 &F) {
	c_number sqr_r = CUDA_DOT(r, r);

	c_number energy = 0.f;
	// this c_number is the module of the force over r, so we don't have to divide the distance
	// vector for its module
	c_number force_mod = 0.f;

	if(sqr_r < MD_sqr_rep_rcut[0]) {
		c_number part = powf(1.f / sqr_r, MD_TSP_n[0] / 2.f);
		energy += 4 * part * (part - 1.f) + 1.f;
		force_mod += 4.f * MD_TSP_n[0] * part * (2.f * part - 1.f) / sqr_r;
	}

	if(int_type == 2) {
		if(sqr_r < MD_sqr_rep_rcut[0]) energy -= MD_TSP_lambda[0];
		else {
			c_number part = powf(1.f / sqr_r, MD_TSP_n[0] / 2);
			energy += 4.f * MD_TSP_lambda[0] * part * (part - 1.f);
			force_mod += 4.f * MD_TSP_lambda[0] * MD_TSP_n[0] * part * (2 * part - 1.f) / sqr_r;
		}

		if(MD_yukawa_repulsion[0]) {
			c_number mod_r = sqrtf(sqr_r);
			c_number r_over_xi = mod_r / MD_TSP_yukawa_xi[0];
			c_number exp_part = expf(-r_over_xi);
			c_number yukawa_energy = MD_TSP_yukawa_A[0] * exp_part / r_over_xi;
			energy += yukawa_energy - MD_yukawa_E_cut[0];
			force_mod += yukawa_energy * (1.f - 1.f / r_over_xi) / (mod_r * MD_TSP_yukawa_xi[0]);
		}
	}

	if(sqr_r > MD_sqr_rcut[0]) energy = force_mod = (c_number) 0.f;

	F.x -= r.x * force_mod;
	F.y -= r.y * force_mod;
	F.z -= r.z * force_mod;
	F.w += energy;
}

__device__ void _fene(c_number4 &r, c_number4 &F, bool anchor = false) {
	c_number sqr_r = CUDA_DOT(r, r);
	c_number sqr_rfene = (anchor && !MD_TSP_only_chains[0]) ? MD_sqr_rfene_anchor[0] : MD_sqr_rfene[0];

	c_number energy = -15.f * sqr_rfene * logf(1.f - sqr_r / sqr_rfene);

	// this c_number is the module of the force over r, so we don't have to divide the distance
	// vector by its module
	c_number force_mod = -30.f * sqr_rfene / (sqr_rfene - sqr_r);
	F.x -= r.x * force_mod;
	F.y -= r.y * force_mod;
	F.z -= r.z * force_mod;
	F.w += energy;
}

__device__ void _particle_particle_bonded_interaction(c_number4 &ppos, c_number4 &qpos, c_number4 &F, bool anchor = false) {
	int ptype = get_particle_type(ppos);
	int qtype = get_particle_type(qpos);
	int int_type = ptype + qtype;

	c_number4 r = qpos - ppos;
	_nonbonded(r, int_type, F);
	_fene(r, F, anchor);
}

__device__ void _TSP_particle_particle_interaction(c_number4 &ppos, c_number4 &qpos, c_number4 &F, CUDABox *box) {
	int ptype = get_particle_type(ppos);
	int qtype = get_particle_type(qpos);
	int int_type = ptype + qtype;

	c_number4 r = box->minimum_image(ppos, qpos);
	_nonbonded(r, int_type, F);
}

// forces + second step without lists
__global__ void tsp_forces(c_number4 *poss, c_number4 *forces, LR_bonds *bonds, CUDABox *box) {
	if(IND >= MD_N[0]) return;

	c_number4 F = forces[IND];
	LR_bonds bs = bonds[IND];
	c_number4 ppos = poss[IND];

	if(bs.n3 != P_INVALID) {
		c_number4 qpos = poss[bs.n3];
		_particle_particle_bonded_interaction(ppos, qpos, F, is_anchor(bs.n3));
	}

	if(bs.n5 != P_INVALID) {
		c_number4 qpos = poss[bs.n5];
		_particle_particle_bonded_interaction(ppos, qpos, F, is_anchor(bs.n5));
	}

	for(int j = 0; j < MD_N[0]; j++) {
		if(j != IND && bs.n3 != j && bs.n5 != j) {
			c_number4 qpos = poss[j];
			_TSP_particle_particle_interaction(ppos, qpos, F, box);
		}
	}

	forces[IND] = F;
}

__global__ void tsp_forces_edge_nonbonded(c_number4 *poss, c_number4 *forces, edge_bond *edge_list, int n_edges, CUDABox *box) {
	if(IND >= n_edges) return;

	c_number4 dF = make_c_number4(0, 0, 0, 0);

	edge_bond b = edge_list[IND];

	// get info for particle 1
	c_number4 ppos = poss[b.from];

	// get info for particle 2
	c_number4 qpos = poss[b.to];

	_TSP_particle_particle_interaction(ppos, qpos, dF, box);

	dF.w *= (c_number) 0.5f;

	int from_index = MD_N[0] * (IND % MD_n_forces[0]) + b.from;
	//int from_index = MD_N[0]*(b.n_from % MD_n_forces[0]) + b.from;
	if((dF.x * dF.x + dF.y * dF.y + dF.z * dF.z + dF.w * dF.w) > (c_number) 0.f) LR_atomicAddXYZ(&(forces[from_index]), dF);

	// Allen Eq. 6 pag 3:
	c_number4 dr = box->minimum_image(ppos, qpos); // returns qpos-ppos
	c_number4 crx = _cross(dr, dF);

	dF.x = -dF.x;
	dF.y = -dF.y;
	dF.z = -dF.z;

	int to_index = MD_N[0] * (IND % MD_n_forces[0]) + b.to;
	if((dF.x * dF.x + dF.y * dF.y + dF.z * dF.z + dF.w * dF.w) > (c_number) 0.f) LR_atomicAddXYZ(&(forces[to_index]), dF);
}

// bonded interactions for edge-based approach
__global__ void tsp_forces_edge_bonded(c_number4 *poss, c_number4 *forces, LR_bonds *bonds) {
	if(IND >= MD_N[0]) return;

	c_number4 F0;

	F0.x = forces[IND].x;
	F0.y = forces[IND].y;
	F0.z = forces[IND].z;
	F0.w = forces[IND].w;

	c_number4 dF = make_c_number4(0, 0, 0, 0);
	c_number4 ppos = poss[IND];
	LR_bonds bs = bonds[IND];

	if(bs.n3 != P_INVALID) {
		c_number4 qpos = poss[bs.n3];
		_particle_particle_bonded_interaction(ppos, qpos, dF, is_anchor(bs.n3));
	}
	if(bs.n5 != P_INVALID) {
		c_number4 qpos = poss[bs.n5];
		_particle_particle_bonded_interaction(ppos, qpos, dF, is_anchor(bs.n5));
	}

	forces[IND] = (dF + F0);
}

// forces + second step with verlet lists
__global__ void tsp_forces(c_number4 *poss, c_number4 *forces, int *matrix_neighs, int *c_number_neighs, LR_bonds *bonds, CUDABox *box) {
	if(IND >= MD_N[0]) return;

	c_number4 F = forces[IND];
	c_number4 ppos = poss[IND];
	LR_bonds bs = bonds[IND];

	if(bs.n3 != P_INVALID) {
		c_number4 qpos = poss[bs.n3];
		_particle_particle_bonded_interaction(ppos, qpos, F, is_anchor(bs.n3));
	}
	if(bs.n5 != P_INVALID) {
		c_number4 qpos = poss[bs.n5];
		_particle_particle_bonded_interaction(ppos, qpos, F, is_anchor(bs.n5));
	}

	const int num_neighs = c_number_neighs[IND];
	for(int j = 0; j < num_neighs; j++) {
		const int k_index = matrix_neighs[j * MD_N[0] + IND];

		c_number4 qpos = poss[k_index];
		_TSP_particle_particle_interaction(ppos, qpos, F, box);
	}

	forces[IND] = F;
}

__global__ void tsp_anchor_forces(c_number4 *poss, c_number4 *forces, int *anchors, TSP_anchor_bonds *bonds) {
	if(IND >= MD_N_stars[0]) return;

	int anchor = anchors[IND];
	TSP_anchor_bonds anchor_bonds = bonds[IND];
	c_number4 r_anchor = poss[anchor];
	c_number4 F = forces[anchor];

	for(int an = 0; an < TSP_MAX_ARMS; an++) {
		int bonded_neigh = anchor_bonds.n[an];
		if(bonded_neigh != P_INVALID) {
			// since bonded neighbours of anchors are in the anchor's neighbouring list, the non-bonded interaction between
			// the two, from the point of view of the anchor, has been already computed and hence the anchor-particle
			// interaction reduces to just the fene
			c_number4 r = poss[bonded_neigh] - r_anchor;
			_fene(r, F, true);
		}
		else break;
	}

	forces[anchor] = F;
}
