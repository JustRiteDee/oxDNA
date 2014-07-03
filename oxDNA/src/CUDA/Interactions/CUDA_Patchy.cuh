/* System constants */
__constant__ int MD_N[1];
__constant__ int MD_n_forces[1];
__constant__ float MD_box_side[1];
__constant__ float MD_sqr_rcut[1];
__constant__ float MD_E_cut[1];
__constant__ float MD_patch_E_cut[1];
__constant__ float MD_patch_pow_alpha[1];
__constant__ int MD_N_patches[2];
__constant__ float4 MD_base_patches[2][CUDA_MAX_PATCHES];
/* texture reference for positions */

#include "../cuda_utils/CUDA_lr_common.cuh"

template <typename number, typename number4>
__device__ number4 minimum_image(number4 &r_i, number4 &r_j) {
	number dx = r_j.x - r_i.x;
	number dy = r_j.y - r_i.y;
	number dz = r_j.z - r_i.z;

	dx -= floorf(dx/MD_box_side[0] + (number) 0.5f) * MD_box_side[0];
	dy -= floorf(dy/MD_box_side[0] + (number) 0.5f) * MD_box_side[0];
	dz -= floorf(dz/MD_box_side[0] + (number) 0.5f) * MD_box_side[0];

	return make_number4<number, number4>(dx, dy, dz, (number) 0.f);
}

template <typename number, typename number4>
__device__ void _particle_particle_interaction(number4 &ppos, number4 &qpos, LR_GPU_matrix<number> &po, LR_GPU_matrix<number> &qo, number4 &F, number4 &torque) {
	int ptype = get_particle_type<number, number4>(ppos);
	int qtype = get_particle_type<number, number4>(qpos);

	number4 r = minimum_image<number, number4>(ppos, qpos);
	number sqr_r = CUDA_DOT(r, r);
	if(sqr_r >= MD_sqr_rcut[0]) return;

	number part = 1;
	for(int i = 0; i < PATCHY_POWER / 2; i++) part /= sqr_r;

	number force_module = PATCHY_POWER * part / sqr_r;
	F.x -= r.x * force_module;
	F.y -= r.y * force_module;
	F.z -= r.z * force_module;

	for(int pi = 0; pi < MD_N_patches[ptype]; pi++) {
		number4 ppatch = {
			po.e[0]*MD_base_patches[ptype][pi].x + po.e[1]*MD_base_patches[ptype][pi].y + po.e[2]*MD_base_patches[ptype][pi].z,
			po.e[3]*MD_base_patches[ptype][pi].x + po.e[4]*MD_base_patches[ptype][pi].y + po.e[5]*MD_base_patches[ptype][pi].z,
			po.e[6]*MD_base_patches[ptype][pi].x + po.e[7]*MD_base_patches[ptype][pi].y + po.e[8]*MD_base_patches[ptype][pi].z,
			0
		};
		for(int pj = 0; pj < MD_N_patches[qtype]; pj++) {
			number4 qpatch = {
				qo.e[0]*MD_base_patches[qtype][pj].x + qo.e[1]*MD_base_patches[qtype][pj].y + qo.e[2]*MD_base_patches[qtype][pj].z,
				qo.e[3]*MD_base_patches[qtype][pj].x + qo.e[4]*MD_base_patches[qtype][pj].y + qo.e[5]*MD_base_patches[qtype][pj].z,
				qo.e[6]*MD_base_patches[qtype][pj].x + qo.e[7]*MD_base_patches[qtype][pj].y + qo.e[8]*MD_base_patches[qtype][pj].z,
				0
			};

			number4 patch_dist = {
				r.x + qpatch.x - ppatch.x,
				r.y + qpatch.y - ppatch.y,
				r.z + qpatch.z - ppatch.z,
				0
			};

			number dist = CUDA_DOT(patch_dist, patch_dist);
			if(dist < SQR(PATCHY_CUTOFF)) {
				number r8b10 = dist*dist*dist*dist / MD_patch_pow_alpha[0];
				number exp_part = -1.001f * expf(-(number)0.5f * r8b10 * dist);

				number4 tmp_force = patch_dist * (5 * exp_part * r8b10);

				torque -= _cross<number, number4>(ppatch, tmp_force);
				F.x -= tmp_force.x;
				F.y -= tmp_force.y;
				F.z -= tmp_force.z;

				// we are in the single bond per patch condition
				return;
			}
		}
	}
}

// forces + second step without lists
template <typename number, typename number4>
__global__ void patchy_forces(number4 *poss, LR_GPU_matrix<number> *orientations, number4 *forces, number4 *torques) {
	if(IND >= MD_N[0]) return;

	number4 F = forces[IND];
	number4 T = make_number4<number, number4>(0, 0, 0, 0);
	number4 ppos = poss[IND];
	LR_GPU_matrix<number> po = orientations[IND];

	for(int j = 0; j < MD_N[0]; j++) {
		if(j != IND) {
			number4 qpos = poss[j];
			LR_GPU_matrix<number> qo = orientations[j];

			_particle_particle_interaction<number, number4>(ppos, qpos, po, qo, F, T);
		}
	}

	T = _matrix_transpose_number4_product<number>(po, T);

	forces[IND] = F;
	torques[IND] = T;
}

template <typename number, typename number4>
__global__ void patchy_forces_edge(number4 *poss, LR_GPU_matrix<number> *orientations, number4 *forces, number4 *torques, edge_bond *edge_list,  int n_edges) {
	if(IND >= n_edges) return;

	number4 dF = make_number4<number, number4>(0, 0, 0, 0);
	number4 dT = make_number4<number, number4>(0, 0, 0, 0);

	edge_bond b = edge_list[IND];

	// get info for particle 1
	number4 ppos = poss[b.from];
	LR_GPU_matrix<number> po = orientations[b.from];

	// get info for particle 2
	number4 qpos = poss[b.to];
	LR_GPU_matrix<number> qo = orientations[b.to];

	_particle_particle_interaction<number, number4>(ppos, qpos, po, qo, dF, dT);

	int from_index = MD_N[0]*(IND % MD_n_forces[0]) + b.from;
	if((dF.x*dF.x + dF.y*dF.y + dF.z*dF.z) > (number)0.f) LR_atomicAddXYZ(&(forces[from_index]), dF);
	if((dT.x*dT.x + dT.y*dT.y + dT.z*dT.z) > (number)0.f) LR_atomicAddXYZ(&(torques[from_index]), _matrix_transpose_number4_product<number>(po, dT));

	// Allen Eq. 6 pag 3:
	number4 dr = minimum_image<number, number4>(ppos, qpos); // returns qpos-ppos
	number4 crx = _cross<number, number4>(dr, dF);
	dT.x = -dT.x + crx.x;
	dT.y = -dT.y + crx.y;
	dT.z = -dT.z + crx.z;

	dF.x = -dF.x;
	dF.y = -dF.y;
	dF.z = -dF.z;

	int to_index = MD_N[0]*(IND % MD_n_forces[0]) + b.to;
	if((dF.x*dF.x + dF.y*dF.y + dF.z*dF.z) > (number)0.f) LR_atomicAddXYZ(&(forces[to_index]), dF);
	if((dT.x*dT.x + dT.y*dT.y + dT.z*dT.z) > (number)0.f) LR_atomicAddXYZ(&(torques[to_index]), _matrix_transpose_number4_product<number>(qo, dT));
}

// forces + second step with verlet lists
template <typename number, typename number4>
__global__ void patchy_forces(number4 *poss, LR_GPU_matrix<number> *orientations, number4 *forces, number4 *torques, int *matrix_neighs, int *number_neighs) {
	if(IND >= MD_N[0]) return;

	number4 F = forces[IND];
	number4 T = make_number4<number, number4>(0, 0, 0, 0);
	number4 ppos = poss[IND];
	LR_GPU_matrix<number> po = orientations[IND];

	int num_neighs = number_neighs[IND];

	for(int j = 0; j < num_neighs; j++) {
		int k_index = matrix_neighs[j*MD_N[0] + IND];

		number4 qpos = poss[k_index];
		LR_GPU_matrix<number> qo = orientations[k_index];
		_particle_particle_interaction<number, number4>(ppos, qpos, po, qo, F, T);
	}

	T = _matrix_transpose_number4_product<number>(po, T);

	forces[IND] = F;
	torques[IND] = T;
}